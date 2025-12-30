---
title: "The Cargo Cult of Good Code"
date: 2022-04-02T00:00:00Z
lastmod: 2023-07-02
expiryDate: 2025-12-30
draft: false
type: post
description: Software design is often reduced to a set of rules and rituals. It's well meaning and sometimes helpful, but it ultimately misses the point.
image: John_Frum_flag_raising-800.jpg
image_caption: Flag raising from the John Frum cargo cult.
discussions:
- url: https://www.reddit.com/r/programming/comments/tu5x9i/the_cargo_cult_of_good_code/
  site: /r/programming
- url: https://www.reddit.com/r/programming/comments/zsgf9f/the_cargo_cult_of_good_code/
  site: /r/programming (again)
- url: https://www.reddit.com/r/programmingcirclejerk/comments/zsvchu/anyone_trying_to_trace_the_logic_of_listpeople_or/
  site: /r/programmingcirclejerk (yikes!)
related:
- /posts/good-interfaces
- /posts/code-structure-experiment
- /posts/code-structure-experiment-part-2
---
{{< img
    src="John_Frum_flag_raising-800.jpg"
    alt="Flag raising from the John Frum cargo cult"
    attr="Flickr user Charmaine Tham"
    attrlink="https://www.flickr.com/photos/charmainetham/420602513/"
    srcset="John_Frum_flag_raising-800.jpg 800w, John_Frum_flag_raising-350.jpg 350w, John_Frum_flag_raising-275.jpg 275w"
    sizes="(max-width: 400px) 275px, (max-width: 900px) 350px, 800px" >}}

[On Writing Well](https://www.amazon.com/dp/0060891548) by William Zinsser is my second favorite book on software design. I know it has nothing to do with programming but let's look at some lightly edited quotes:

> Clear thinking becomes clear coding; one can't exist without the other.

> Look for the clutter in your code and prune it ruthlessly.

> Rewriting is the essence of programming.

If that last one doesn't seem to apply, consider that code isn't really written so much as beaten it into shape and then refactored.

Of course, writing code is different enough from writing prose that On Writing Well can't be my favorite programming book. But that spot goes to John K. Ousterhout's [A Philosophy of Software Design](https://www.amazon.com/dp/173210221X), which has a similar message: write clearly, remember your audience, and plan to rewrite it.

The central message of the book is that complexity is the enemy. After all, if working code were enough, then we'd compile the code once and throw away the source. We keep the source so we can modify the program, but it's as useless as compiled code if you can't understand it. So the goal is to reduce the complexity as much as possible.

Unfortunately, the conventional wisdom that's been handed down around software design is more about following a set of rules and best practices than reducing complexity. I'm sure the focus in the beginning was on producing simple code. But the caveats and clarifications were lost somewhere and what we have left is the form without the principles.

This is what I'm calling the [Cargo Cult](https://en.wikipedia.org/wiki/Cargo_cult) of Good Code. Its practitioners are well-intentioned, but they miss the point. They follow the rules but don't understand them. It's merely the form of good programming. They may be confused at times when the benefits of clear code don't rain down from heaven, but they can always find a missed step to explain it away.

## Don't Repeat Yourself

Somewhat ironically, the Cargo Cult of Good Code has a mantra: Don't Repeat Yourself. In general, it's good advice. And it's hard to criticize without sounding like an advocate for standing in a corner chanting to yourself, but I will try. Consider this example of a pair of HTTP handlers (Go is the language of the day, but I won't dwell on the specifics of the language):

```go
func listPeople(w http.ResponseWriter, r *http.Request) {
	params := r.URL.Query()

	var alive bool
	if rawAlive := params.Get("alive"); rawAlive != "" {
		var err error
		alive, err = strconv.ParseBool(rawAlive)
		if err != nil {
			http.Error(w, "invalid alive parameter", http.StatusBadRequest)
			return
		}
	}

	people, err := db.ListPeople(alive)
	// ...
}

func listDogs(w http.ResponseWriter, r *http.Request) {
	params := r.URL.Query()

	var alive bool
	if rawAlive := params.Get("alive"); rawAlive != "" {
		var err error
		alive, err = strconv.ParseBool(rawAlive)
		if err != nil {
			http.Error(w, "invalid alive parameter", http.StatusBadRequest)
			return
		}
	}

	dogs, err := db.ListDogs(alive)
	// ...
}
```

`listPeople` and `listDogs` are a lot alike. They both handle an identical `alive` query string parameter and then call a function to presumably fetch a list of either persons or dogs filtered by the level of aliveness (with apologies to Miracle Max, this is a boolean).

This code is repetitive. In fact, the only difference is the function we call at the end, so let's "DRY it out", as they say:

```go
func listPeople(w http.ResponseWriter, r *http.Request) {
	listMammals(w, r, db.ListPeople)
}

func listDogs(w http.ResponseWriter, r *http.Request) {
	listMammals(w, r, db.ListDogs)
}

func listMammals(w http.ResponseWriter, r *http.Request, lister func(bool) (interface{}, error)) {
	params := r.URL.Query()

	var alive bool
	if rawAlive := params.Get("alive"); rawAlive != "" {
		var err error
		alive, err = strconv.ParseBool(rawAlive)
		if err != nil {
			http.Error(w, "invalid alive parameter", http.StatusBadRequest)
			return
		}
	}

	mammals, err := lister(alive)
	// ...
}
```

If the goal was to eliminate duplication, then mission accomplished. But that's not really the goal, the goal is simplicity. So is it easier to understand and modify this code after our change?

Anyone trying to trace the logic of `listPeople` or `listDogs` now has an additional function, `listMammals`, to keep track of. There's no way to understand either handler without looking at `listMammals`. And the code in `listMammals` is necessarily more generic and therefore more complicated. The original code was hardly a great example of good code, but it was at least easy to follow.

The bigger problem comes when we try to modify this code. `listPeople` and `listDogs` weren't actually duplicates. I know the code was nearly identical, but that was a coincidence. They were destined to morph in different directions, and now they're fused together like an Egyptian god. We can't say how this code will need to change, but I do know that dogs are microchipped and people get married. Unless we break those functions apart (or engage in some really un-clean code) we'll have to deal with married dogs and microchipped people.

The perverse thing about it though: the mantra was right. The code repeated itself and it needed to be cleaned up. Our problem was applying the rule without understanding the principle behind it.

To clean it up properly we need a function that can process our `alive` query string parameter for us. Let's try again:

```go
func listPeople(w http.ResponseWriter, r *http.Request) {
	alive, err := getBoolParam(r, "alive")
	if err != nil {
		http.Error(w, "invalid alive parameter", http.StatusBadRequest)
		return
	}

	people, err := db.ListPeople(alive)
	// ...
}

func listDogs(w http.ResponseWriter, r *http.Request) {
	alive, err := getBoolParam(r, "alive")
	if err != nil {
		http.Error(w, "invalid alive parameter", http.StatusBadRequest)
		return
	}

	dogs, err := db.ListDogs(alive)
	// ...
}

// getBoolParam grabs a query string parameter by name.
//
// Defaults to false if the query string value is omitted. Returns an error if
// the query string value cannot be parsed as a bool.
func getBoolParam(r *http.Request, name string) (bool, error) {
	if raw := r.URL.Query().Get(name); raw != "" {
		return strconv.ParseBool(raw)
	}

	return false, nil
}
```

`getBoolParam` helps. We have another name to juggle, but you can probably guess what it does without looking at it. So it's removed some of the burden from the reader. When this code needs to change, we can add a new `getBoolParam` call to either handler without affecting the other one. This could probably be improved a bit further, but I'll leave it there.

## Constants
The Cargo Cult of Good Code loves constants. This is also hard to argue with because constants can make better code. Consider an example from when I worked at a place that I'll call Foo Bar Corp:

```go
const FooBarCorp = "Foo Bar Corp"

// elsewhere..
fmt.Printf("Copyright %d %s", time.Now().Year(), FooBarCorp)
```

Did this constant make it easier to understand that code? Not really. Consider the alternative:

```go
fmt.Printf("Copyright %d Foo Bar Corp", time.Now().Year())
```

It's not much, but I find the second version is a little easier to follow since I don't have to find the definition of `FooBarCorp`.

Did this constant make it easier to modify the code? I suppose it could. But in this case, the constant was only used once, so it didn't matter. If it were used in more places, changing the value would still require checking that the new value was appropriate for all those other cases. This was a wash for reducing complexity, but a win for the cargo cult.

## Modular Code
Let's look at our `listPeople` HTTP handler again. Some time has passed and more features were added:

```go
func listPeople(w http.ResponseWriter, r *http.Request) {
	var filters db.PeopleFilters
	var err error

	filters.Alive, err = getBoolParam(r, "alive")
	if err != nil {
		http.Error(w, "invalid alive parameter", http.StatusBadRequest)
		return
	}

	filters.Married, err = getBoolParam(r, "married")
	if err != nil {
		http.Error(w, "invalid married parameter", http.StatusBadRequest)
		return
	}

	filters.ResidentOfOhio, err = getBoolParam(r, "resident_of_ohio")
	if err != nil {
		http.Error(w, "invalid resident_of_ohio parameter", http.StatusBadRequest)
		return
	}

	// ... several more filters...

	people, err := db.ListPeople(filters)
	// ...
}
```

The number of query string parameters has grown and the function is quite long indeed. If you're of the school of thought that says functions should be short (or you're nudged in that direction by a [static analysis tool](https://github.com/fzipp/gocycloyo)) you'll want to split this up:

```go
func listPeople(w http.ResponseWriter, r *http.Request) {
	var filters db.PeopleFilters

	err := getListPeopleFilters(r, &filters)
	if err != nil
		http.Error(w, "invalid alive parameter", http.StatusBadRequest)
		return
	}

	people, err := db.ListPeople(filters)
	// ...
}

func getListPeopleFilters(r *http.Request, filters *db.PeopleFilters) error {
	filters.Alive, err = getBoolParam(r, "alive")
	if err != nil {
		return fmt.Errorf("invalid alive parameter")
	}

	filters.Married, err = getBoolParam(r, "married")
	if err != nil {
		return fmt.Errorf("invalid married parameter")
	}

	filters.ResidentOfOhio, err = getBoolParam(r, "resident_of_ohio")
	if err != nil {
		return fmt.Errorf("invalid resident_of_ohio parameter")
	}

	return nil
}
```

Is this easier to understand? I don't think so. If we want to understand `listPeople` we will still have to understand the code in `getListPeopleFilters`, but now we have to look somewhere else. At best, we've moved the complexity, we haven't reduced it. But if all you know is that "functions should be short", this probably looks like better code to you. And that's the trouble with the Cargo Cult of Good Code, it mimics good software design but misses the point entirely.

---

For a long time, I was focused on following a set of rules for writing good code, that often didn't seem to work. I [wrote about one attempt to solve this dilema](https://pboyd.io/posts/code-structure-experiment/) (not that I recommend reading it). I was trying to write good code, but I lacked the criteria to judge good code from bad code. All I had to go on was a fuzzy, and entirely subjective, idea of "cleanliness". I am grateful that someone pointed me to [A Philosophy of Software Design](https://www.amazon.com/dp/173210221X). We can quibble about the implications, but the understanding that reducing complexity is the point of structuring code was enormously helpful to me, and I hope it is to you as well.
