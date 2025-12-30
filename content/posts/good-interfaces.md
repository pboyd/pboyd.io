---
title: "Designing Good Interfaces"
date: 2023-03-10
draft: false
type: post
description: A look at designing clean code interfaces, illustrated with examples.
related:
- /posts/cargo-cult-of-good-code
- /posts/code-structure-experiment
- /posts/code-structure-experiment-part-2
discussions:
- url: https://news.ycombinator.com/item?id=35164997
  site: Hacker News
---
_Technician:_ Welcome to Custom Lube, how can I help you?{{< br >}}
_Me:_ I need an oil change.{{< br >}}
_Technician:_ OK, you can hop on out. Where is the oil you want to use?{{< br >}}
_Me:_ I didn't bring any oil. I expected you would supply that.{{< br >}}
_Technician:_ That's a common misunderstanding. At Custom Lube, we don't supply oil or anything else. We want our customers to have exactly what's right for them and their cars. We keep our operation as simple as can be. A well-oiled machine, you might say. All that inventory would add complexity, which would add cost that we'd have to pass on to you. You don't want that now, do you?{{< br >}}
_Me:_ Well, no..{{< br >}}
_Technician:_ Anyway, most customers are better off blending their own oil. A conventional 10W-30 base, with a little high mileage and a dash of synthetic, is a popular choice. Sometimes I'll use a bit of lawnmower oil in mine, just for that small engine vigor. One customer has a blend of over 10 different oils! A beautiful concoction, I've asked for the recipe, but..{{< br >}}
_Me (interrupting):_ Hey, I'm sure it's delightful, but I just need regular oil, you must be able to do something? This is an oil change shop, right?{{< br >}}
_Technician:_ Of course, but I wouldn't recommend it. You would do better with a blend made just for your car.{{< br >}}
_Me:_ Just do what you can. An off-the-shelf oil will be fine.{{< br >}}
_Technician:_ If you insist, I'm not here to argue. One customer adds a pinch of salt to his oil for luck, but it's not my place to say anything.

The car is ready in record time, and the bill is less than expected. For all the oddity, I think, at least this place is efficient. I begin to drive away, but halfway out of the bay, I hear a sound like an ax hitting wood, followed by grinding and then silence as the engine seizes. Furious, I get out and find the attendant.

_Me:_ What kind of oil did you put in my car?{{< br >}}
_Technician:_ Like I said, we don't supply oil, but as promised I did what I could. Don't worry, I didn't charge you for a full oil change, I only charged you to drain the oil. It's ready for you to add your off-the-shelf oil.{{< br >}}
_Me:_ But, my car...{{< br >}}
_Technician:_ Would you like to hear about our sister company Custom Auto Repair?

I know it's absurd. And yet how many times have you seen code like this Go example:
```Go
func ChangeOil(c Car, oil []BottleOfOil) {
	drainOil(c)
	for _, bottle := range oil {
		addOil(c, bottle)
	}
}
```

The dependency (oil, in this example) is an argument, not because anyone cares to customize it, but to simplify the implementation. Leave the argument `nil`, and the function will silently leave the object in a bad state.

What the caller probably wanted was more like this:
```Go
type OilType uint

const (
	Synthetic OilType = iota
	Conventional
)

func ChangeOil(c Car, oilType OilType) error {
	oil, err := inventory.GetOil(oilType)
	if err != nil {
		return err
	}

	drainOil(c)
	for _, quart := range oil {
		addQuartOfOil(c, quart)
	}

	return err
}
```

Better? Perhaps. It's definitely better for me, a mechanically ignorant driver who is happy to delegate this task to someone else. But not everyone is like me; somewhere out there is someone who would prefer to supply their own oil but not change it themselves.

That's why you must understand who's calling your code and design an interface that meets their needs. I'll leave the imaginary examples behind and explain what I mean through a somewhat real-world program, but it requires some background information, so bear with me.

## Greek Numbers
Pompeii contains this bit of graffiti preserved by the volcanic ash: Φιλω ης αριθμος ϕμε. Or "I love her whose number is _phi mu epsilon_ (545)".[^1] This is an example of Isopsephy where the letters in a word or phrase are summed to make a number. That's right, rather than declare his[^2] love in person, our would-be lover wrote a riddle in graffiti. I don't know if this strategy worked or much of anything about these two. It had to be written before the volcano erupted in 79 CE, and the love interest was a woman, but that's it. In the movie version of their lives, I imagine them gazing into one another's eyes as the pyroclastic flow creeps closer until the movie fades out and the credits begin to roll. But most inhabitants escaped Pompeii, so there's a good chance they lived a long and happy life.

Anyway, Isopsephy was probably obvious to anyone literate in Greek at the time. The same symbols were used for letters and numbers, so Isopsephy is simply adding the letters as if they were numbers. For example, take Ἀφροδίτη (Aphrodite--no doubt the goddess our graffiti artist was praying to) and convert each letter to its numeric equivalent:
```
Α = 1
φ = 500
ρ = 100
ο = 70
δ = 4
ί = 10
τ = 300
η = 8
```
This sums to 993 (ϡϙγ, if you prefer).

To recap, we have an algorithm that's easy to compute, hard to reverse, and used to confirm that a secret is known without having to share the secret. Sound familiar? It's a hash function! It's weak by modern standards, but a hash function nonetheless.

> Every man has two deaths, when he is buried in the ground and the last time someone says his name.{{< br >}}
> -- Ernest Hemingway[^3]

If you believe that, and we can find this woman's name, we can resurrect her, so to speak, from that second kind of death. That's the problem this program will attempt to solve.

Thanks to Oxford University, we have what we need for a dictionary attack: the [Lexicon of Greek Personal Names](https://www.lgpn.ox.ac.uk/) (LGPN). It even has a searchable online database. So the program will compute the _arithmos_ of each name and see if we have a plausible match.

## User Interface
This article is really focused on APIs (in the sense of code libraries, not REST, etc.), but the process of designing a good API overlaps with designing any other interface. And an application with good code and a bad UI is still useless. So let's look at the UI first.

Like any UI designer, we need to start by understanding what the user is trying to do and what they'll need. In this case, understanding the user is remarkably simple because I will probably be the only user ever. Personally I don't need or even want a fancy graphical UI, I simply want to input a number and see potential names:

```sh
$ ./antisopsephy 545
Possible Name 1
Possible Name 2
...
```

Programmer me needs more details, but user me doesn't care. So the programmer side of my split personality will have to figure that out. Putting the wishes of the caller before the wishes of the implementer is necessary for a good design. There is more to a good UI, even a minimal CLI like this, but let's move on.

## Downloading names
The LGPN has a endpoint which returns every names in their database as JSON, which is absolutely perfect for this program. But the response almost 5 MB in size which would be slow to download and parse for each run. Also the LGPN is a free service and I don't want to abuse it, so the program needs to cache that response.

When designing an interface I find it helpful to start by writing the code that will call it. In this case the `main` function of the program needs to iterate over every name. Ideally, it would like something like this:

```Go
for _, name := range lgpn.Names() {
	if magicFunction(name) == searchNumber {
		// It's a match!
	}
}
```

Reality, however, is never ideal. `Names()` could fail, so we'll need an error. This also implies that `Names()` returns the whole list in memory. There are about 40,000 names, so it would easily fit, but since we only need one name at a time why load them all at once? Trying again:

```Go
names, err := lgpn.Names(ctx)
if err != nil {
	// handle this!
}
for name := range names {
	// Same as before
}
```

In this version, `Names()` returns a channel that will be closed when all the names have been sent or the context is canceled. This is one way to implement an iterator in Go, it uses a channel like a generator in other languages.

Our ideal interface lacks anything related to the LGPN service or the cache. This code in `main` is focused on the search algorithm, so URLs and cache locations aren't relevant. They belong to a lower level of abstraction.

Of course, pushing the details down only works because we know what the caller needs. If, instead of an application, this were a general library making assumptions about where cache files should be stored would be bad form. Good interfaces are not one size fits all. They must be designed for a specific case.

Next, I like to stub out the functions and types:
```Go
func Names(ctx context.Context) (<-chan string, error) {
	return nil, nil
}
```

One crucial part of the interface is missing: the documentation. A user of this code should be able to understand how to use it from the docs alone. If someone looks at the implementation for details to call the function,  the docs are incomplete.

```Go
// Names returns a channel that will receive every name in the Lexicon of Greek
// Personal Names (LGPN). If the names cannot be retrieved an error is
// returned.
//
// The returned channel will be closed after the last name has been read or
// when the passed context is closed.
func Names(ctx context.Context) (<-chan string, error) {
	return nil, nil
}
```

When the docs are written first they become something of a spec. I often rewrite them later, but the result is always better documentation and probably better code.

## Tests
The interface to fetch names is not the least bit configurable. This was intentional, but it complicates the unit tests. I don't want my test to download a file from the internet (that would be slow, flaky, and possibly abusive to the LGPN's web service). I also want to control the cache file in a way that doesn't destroy the cache used during normal execution.

There are several ways to handle this, but I will opt for another interface with more options. It's pretty common to have a simple interface for most users that's a front-end to a more powerful and more complicated interface. We'll start by stubbing the interface:
```Go
// client handles fetching and caching of names from the LGPN.
type client struct {
}

// newClient returns a client which will connect to the LGPN using lgpnBase for
// the URL and cache results in cacheDir.
//
// lgpnBase should contain the scheme and hostname of the URL. For example,
// "http://clas-lgpn2.classics.ox.ac.uk" or "http://localhost:8080". If
// lgpnBase is an invalid URL newClient will panic.
//
// If cacheDir is an empty string a suitable directory will be selected based
// of the system platform. If the cacheDir does not exist an attempt will be
// made to create it. If there is any problem with the cacheDir newClient will
// panic.
func newClient(lgpnBase, cacheDir string) *client {
	return nil
}

// Names is the internal implementation of the package-level Names function.
// See that function for the documentation.
func (c *client) Names(ctx context.Context) (<-chan string, error) {
	return nil, nil
}
```

These functions are not public (the lowercase first letter in `client`). The only callers of this code will be tests in the same package, so they don't need to be exported. If I export something I'll have to maintain it, and I see no reason to make unnecessary work for myself.

This more advanced interface enables us to write a unit that uses a mock web server instead of the real web service. There is a danger here that we'll miss a bug in the little bit of code that wasn't tested. But this untested code is minimal, and unit tests are not meant to replace all other testing.

## Implementation
I know it's taken a while to get to the "real code." Designing an interface when you could be cranking out code may seem like a waste of time. But the real waste of time is ignoring the design and paying for it whenever someone needs to understand the mess you made. And it actually doesn't take that long.

The implementation to download names is [nothing special](https://github.com/pboyd/antisopsephy/tree/master/internal/lgpn). It was mostly a matter of writing a test and filling out the stubbed methods. After the 3rd or 4th private method I wrote named `cache*` I split that code into another internal `cache` struct. Which did require another brief bit of interface design, but the process was the same the above.

## Searching
Now that we can iterate through the names, we can calculate the "number" of each name. This is straightforward, so the interface can be a single function call, which we will call like this:
```Go
for name := range names {
	n, err := isopsephy.Calculate(name)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invalid name: %v\n", err)
		continue
	}

	if n == number {
		fmt.Println(name)
	}
}
```

Nothing fancy, but that's fine. It doesn't need to be. The `Calculate` function interface is much like you probably expect:

```Go
// Calculate finds the "number" of a word by summing the numeric equivalent of
// each Greek letter. If an unrecognized character is encountered an error is
// returned.
func Calculate(word string) (int, error) {
...
}
```

With that, the program is complete. It can search for the number of any Greek name and report matches, which is all I wanted.

## Results
Searching for 545 (the number from the graffiti) gave me 25 potential names. Most of those can be excluded because they were either male names or from the wrong time period. Unfortunately, none were very likely matches, so the best I can do is pick relatively popular names from the time period. My two favorites are:

- Γάουιλλα (Gaoülla)
- Κυθερία (Kütheria)

Of course, there's no way to confirm either of these. For all I know, the name was never recorded, or our would-be lover added it incorrectly. Such is life.

If you want to play with this program I know of two similar inscriptions from the Ancient Graffiti Project: [1](http://ancientgraffiti.org/Graffiti/graffito/AGP-SMYT00221) [2](http://ancientgraffiti.org/Graffiti/graffito/AGP-SMYT00242), and there are probably others.

If you want to know more about software design, I'd recommend [A Philosophy of Software Design](https://web.stanford.edu/~ouster/cgi-bin/book.php) by John Ouserhout. Many of the ideas in this post are his.

The source code for this program is on [github](https://github.com/pboyd/antisopsephy/).

[^1]: https://en.wikipedia.org/wiki/Isopsephy I've seen numerous references to this inscription, but I can't find an authoritative source. If you know of one, I'd love to know about it: [email me](mailto:paul@pboyd.io).
[^2]: Or her, the gender of the author is also unknown. But this sounds like adolescent male behavior to me.
[^3]: I need to work on my research skills because I can't find a good source for this, either.
