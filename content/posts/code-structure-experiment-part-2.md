---
title: "An experiment on code structure - Part 2"
date: 2019-12-26
draft: false
type: post
related:
- /posts/code-structure-experiment
---

_This is a follow-up to [an experiment on code
structure](/posts/code-structure-experiment/). To recap, I built two versions
of a back-end for a [simple web app][1] with statistics about commercial
airline flights. [`backendA`][2] had no real design behind it, it was just
whatever fell out of keyboard. [`backendB`][3] was a structure that I've been
using for the past couple years, it isolates dependencies, and uses interfaces
with dependency injection. The two versions produce identical output, only the
structure of the code is different._

[1]: https://flightranker.com
[2]: https://github.com/pboyd/flightranker-backend/tree/master/backendA
[3]: https://github.com/pboyd/flightranker-backend/tree/master/backendB

I goofed up with my experiment and never chose a criteria to judge it by.
Needless to say, it ended inconclusively and all I could do was stick with my
status quo.

Fortunately, a reader sent me a recommendation to read ["A
philosophy of software design" by John Ousterhout][4]. The book argues that
good software design produces so called "deep modules", that is powerful
implementations hidden behind simple interfaces. Complexity is therefore the
enemy, but complexity gets a special definition: "anything related to the
structure that makes the code hard to understand or modify". So not reducing
complexity in general, just the complexity created by the structure of the
code.[^1]

[4]: https://www.amazon.com/Philosophy-Software-Design-John-Ousterhout-ebook/dp/B07N1XLQ7D/ref=sr_1_3

It may not sound like it at first, but "modules should be deep" contradicts a
lot of common advice about software design (a module, by the way, is any
division of code--function, class, package, etc.). Such as, making functions
small. Ousterhout actually encourages large functions. Short functions may be
simple by themselves, but lots of them together create a complicated system.

I'm not sure that that simplicity is better than every other software design
virtue. But I certainly agree that simplicity is better than complexity, and it
at least gives me a reasonable way to judge my experiment. The winning design
is the simpler one.

It isn't even a close contest by this standard. Take the resolver function for
the `airport` GraphQL query. It handles queries like this:
`{airport(code:"JFK"){name,city,state}}` which looks up an airport by code.

Here's the version from `backendA`:

```go
func resolveAirportQuery(db *sql.DB) graphql.FieldResolveFn {
	return graphQLMetrics("airport",
		func(p graphql.ResolveParams) (interface{}, error) {
			code := getAirportCodeParam(p, "code")
			if code == "" {
				return nil, nil
			}

			row := db.QueryRow(`
				SELECT
					code, name, city, state, lat, lng
				FROM
					airports
				WHERE
					is_active=1 AND
					code=?
			`, code)

			var a airport
			err := row.Scan(&a.Code, &a.Name, &a.City, &a.State, &a.Latitude, &a.Longitude)
			if err != nil {
				if err == sql.ErrNoRows {
					return nil, nil
				}
				return nil, err
			}

			return &a, nil
		},
	)
}
```

It's easy to see how this works. It isn't extremely short, it operates on more
than one level of abstraction, and it is concerned with things unrelated to
it's objective (e.g. the `graphQLMetrics` wrapper). But there are no mysteries
here. If you need to add another field or make some other small change it won't
get in your way.

Now compare that with the equivalent in `backendB`:

```go
func (p *Processor) resolveAirportQuery(params graphql.ResolveParams) (interface{}, error) {
	code := p.getAirportCodeParam(params, "code")
	if code == "" {
		return nil, nil
	}

	return p.config.AirportStore.Airport(params.Context, code)
}
```

It's much shorter. If you're content with the abstraction provided by
`AirportStore.Airport` then this is everything you need. If not, you'll need to
dig deeper. If you know this codebase pretty well you can probably jump right
to the relevant code. Otherwise, you'll have to figure out what `p.config` is:

```go
type Processor struct {
	config ProcessorConfig
	schema graphql.Schema
}
```

It's a `ProcessorConfig`:

```go
type ProcessorConfig struct {
	AirportStore     app.AirportStore
	FlightStatsStore app.FlightStatsStore
}
```

I'll spare you the details and just give a summary:

* `p.config.AirportStore` is an `app.AirportStore`, so go look in the `app` package
* `app.AirportStore` is an interface with an `Airport` method
* `AirportStore` isn't implemented in `app`, the programmer has to go back and
  see how the `Processor` gets a `ProcessorConfig`
* The `ProcessorConfig` is passed in when the `Processor` is created. It's up
  to the caller to supply a valid `ProcessorConfig` with a valid `AirportStore`
  instance.
* Hopefully the programmer thinks to check `main`, where they'll see that
  `AirportStore` is a `*mysql.Store`

Now, finally, in the `mysql` package we'll find:

```go
func (s *Store) Airport(ctx context.Context, code string) (*app.Airport, error) {
	code = strings.ToUpper(code)

	row := s.db.QueryRow(`
		SELECT
			code, name, city, state, lat, lng
		FROM
			airports
		WHERE
			is_active=1 AND
			code=?
	`, code)

	var a app.Airport
	err := row.Scan(&a.Code, &a.Name, &a.City, &a.State, &a.Latitude, &a.Longitude)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &a, nil
}
```

That doesn't seem simple. `backendA` is the simpler design.

`backendB` is more flexible though. Everything is isolated and used through an
interface, so I can just replace those interface implementations. I could
support an additional database MySQL, or add a caching layer just by writing a
new `Store` implementation. If I actually needed to do any of that, `backendB`
might have had a good design, but I didn't. And that flexibility caused
complexity and that's why `backendA` is simpler.

I made another version of the flightranker backend, [`backendC`][5], that
followed Ousterhout's book. I settled on three packages:

[5]: https://github.com/pboyd/flightranker-backend/tree/master/backendC

* `store` - high-level application functions that pull data from MySQL 
* `server` - HTTP server handling GraphQL queries
* `main` - just an entry point

`server` is responsible for everything related to HTTP. This is a break from
`backendB` where `main` started the server, `http` made a handler and `graphql`
had most of the functionality.

All the code in `backendB` that reads environment variables is in the `main`
package. That made `main` aware of things it didn't really need (e.g. MySQL
connection information). With `backendC` I decided to read the environment
variables from deeper down, so a module is responsible for its' whole problem.

`backendB`'s `main` package also used dependency injection to put the right
implementation of an interface in the right place. But, again, this was
needless complexity since there there were single implementations. For
`backendC`, there's only one `store` implementation, and since it can read it's
own config, it's simple enough for `server` to create an instance directly.

Between pushing the configuration down and removing dependency injection,
`backendC`'s `main` function is really short:

```go
func main() {
	server.Run()
}
```

That's the equivalent of ~30 lines of code in `backendB`.

Earlier we looked at the airport resolver in `backendA` and `backendB`. Here's
the equivalent for `backendC`:

```go
// airportQuery defines a GraphQL query that accepts an airport code and
// responds with information about the airport.
func airportQuery(st *store.Store) *graphql.Field {
	return &graphql.Field{
		Type:        airportType,
		Description: "get airport by code",
		Args: graphql.FieldConfigArgument{
			"code": airportCodeArgument,
		},
		Resolve: func(params graphql.ResolveParams) (interface{}, error) {
			code, _ := params.Args["code"].(string)
			airport, err := st.Airport(params.Context, code)

			if err == store.ErrInvalidAirportCode {
				return nil, nil
			}

			return airport, err
		},
	}
}
```

I decided to in-line the `Resolve` functions in the `graphql.Field`
definitions. I think they're easier to understand together.

This isn't as complete as `backendA`, but the `store.Airport` abstraction is
good enough for some purposes. And if it's not good enough, you can at least
see right away that `store.Airport` comes from `store.Store`.

`backendC` is simpler than `backendB`, that's pretty obvious. It's not as clear
of a comparison between `backendA` and `backendC`, but I think `backendC` is
simpler than `backendA` too. There's a limit to what a person can keep in their
head at one time. `backendA` doesn't have many abstractions and it can be hard
to follow the logic at times.

For instance, the airport resolver in `backendA` was simple enough to not be a
problem, but the more complicated resolvers are a challenge to keep straight.
Like the all-time airline stats resolver in [`backendA`][6]. It has very few
abstractions, and those that are there (e.g. `isAirportCode`) are "shallow",
and don't remove many details from the programmer.

[6]: https://github.com/pboyd/flightranker-backend/blob/master/backendA/airline_stats.go#L11

Now look at the equivalent in [`backendC`][7]. It's not perfect, but the
`store.FlightStats` call does a big portion of the job, and let's the
programmer get that much of the problem out of their head.

[7]: https://github.com/pboyd/flightranker-backend/blob/master/backendC/server/stats.go#L40

The main thing I learned through all this is that I actually have to design
software. I was relying too much on a "standard" design which usually didn't
fit. A standard structure has to be flexible, but every bit of flexibility
costs a bit of simplicity. 

[^1]: If the special definitions bug you, just remember the title of the book contains the word "philosophy".
