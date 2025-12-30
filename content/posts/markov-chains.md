---
title: "Markov Chains"
date: 2018-08-12T11:00:00Z
draft: false
type: post
---
The first time I ever heard of a Markov chain was overhearing a conversation at
work. My coworker was reading generated text from a Markov chain of the King
James Bible, and was commenting on how ghastly the produced text was. Here's a
sample,

> Thus saith the children of the liver of God and the tabernacle and forsake my
> doors of the breast and she sitteth in Seir most holy in at an homer of
> Pharez and ye may enjoy the needy

Hmm..

Markov chains sounded like an amusement I could live without and ignored it
accordingly. Which was a shame, because they actually have serious
applications. Google's [PageRank](https://en.wikipedia.org/wiki/PageRank)
algorithm is a prominent example. Otherwise, they're used for DNA sequencing,
speech recognition and a whole lot more.

Even the text generator isn't entirely useless. My smartphone suggests the next
word based on the last word entered. I don't know how that's built, of course,
but it could be a Markov chain. Perhaps if I only sent text messages quoting
the King James Bible, it would eventually suggest "children of the liver".

Markov chains were invented by Andrey Markov,a Russian mathematician who lived
in St. Petersburg during the end of the Russian Empire. Markov was outspoken
and rebellious throughout his life, which led to a feud with another
mathematician, Pavel Nekrasov. Markov and Nekrasov held opposing views on
everything from religion to politics, and they frequently quarrelled over all
of it.

In 1902, Nekrasov published a paper in support the Russian Orthodox Church's
stance on free will, which claimed that the law of large numbers requires
independence.

In case it's been a while since you studied statistics. The law of large
numbers predicts, for example, that a coin will land on heads half the time if
it's repeatedly flipped. Since coin flips don't depend on the result of the
previous coin flip, they are *independent* events. If I draw a card from a deck
of playing cards it has a 1:4 chance to be a heart. If I draw a second card
(without replacing the first one), the chances of drawing a heart has changed
slightly (either up or down), so that's a *dependent* event.

Markov was an atheist, and had no intention of leaving Nekrasov's "abuse of
mathematics" unchallenged. So he invented a chain of events, where each event
depends on the previous one, but the law of large numbers still holds. Thus
disproving Nekrasov's claim.

Markov used this chain to study the distribution of vowels and consonants in
text. It's simple enough to do by hand. For instance, here's the opening of
(Markov's contemporary, and fellow St. Petersburg resident) Leo Tolstoy's War
and Peace:

> Well, Prince, so Genoa and Lucca are now just family estates of the
> Buonapartes.

I'm using `c` for consonant, `v` for vowel, `w` for "word breaks" (spaces and
the beginning and end) and punctuation is removed:

```
wcvccwccvccvwcvwcvcvvwvccwcvccvwvcvwcvcwcvccwcvcvcvwvccvcvcwvcwccvwcvvcvcvccvcw
```

Now just count up the combinations and calculate a probability. For instance,
there are 37 `c`'s and 21 `cv`'s, so 21 out of 37 consonants are followed by
vowels or about 57%. Here's all the combinations:

```
37 consonants:
    cv: 57% (21)
    cc: 24% (9)
    cw 19% (7)

27 vowels:
    vc: 67% (18)
    vw: 26% (7)
    vv: 7% (2)

14 spaces:
    wc: 71% (10)
    wv: 29% (4)
    ww: 0% (0)
```

That was 79 events, which I found tedious. Markov used a similar
technique on 20,000 characters from [Eugene
Onegin](https://en.wikipedia.org/wiki/Eugene_Onegin), and subsequently
analyzed 100,000 characters of a [novel](https://archive.org/details/yearsofchildhood00aksa).

That seems like a better job for a computer. The manual algorithm translates to
a computer, more or less. First the data structure:

```go
type Chain map[interface{}]*Link

type Link struct {
	Value    interface{}
	Children []*ChildLink
}

type ChildLink struct {
	*Link
	Count int
}
```

This is in [Go](https://golang.org), but the language doesn't matter much. 
If you're unfamiliar with Go, just know that:

* `interface{}` is basically an unspecified type
* `ChildLink` has all the fields from `Link` plus `Count`

The main point is that each `Link` has child `Links`s. And `ChildLinks`s
have an associated `Count` of the number of times that child has been seen in
relation to the parent.

`Chain` is just a pool of `Links`. The structure is recursive, and it's
important that `Link` value's aren't duplicated. A map of values to links is a
simple way to accomplish that.

Items in a Markov chain are technically linked with a probability, not a count.
But that makes it difficult to insert items, because each additional item
requires recalculating the probability for it's siblings. It's simple enough to
calculate the probability from `Count` and the sum of all the sibling's
`Count`s.

New `Link`s are inserted into `Chain`, and a reference is added to the parent's
`Children`. To strengthen an existing `Link`, only the `Count` needs to be
incremented.

```go
func (c Chain) Increment(parent, child interface{}) {
	link := c.getOrCreateLink(parent)

	childLink := link.Find(child)
	if childLink == nil {
		childLink = &ChildLink{
			Link: c.getOrCreateLink(child),
		}
		link.Children = append(link.Children, childLink)
	}

	childLink.Count++
}

func (c Chain) getOrCreateLink(value interface{}) *Link {
	if _, ok := c[value]; !ok {
		c[value] = &Link{
			Value:    value,
			Children: []*ChildLink{},
		}
	}

	return c[value]
}

func (l *Link) Find(value interface{}) *ChildLink {
	for _, l := range l.Children {
		if l.Value == value {
			return l
		}
	}

	return nil
}
```

That's it for the `Chain` itself. To use it to count vowels and consonants,
I'll need to introduce another data type:

```go
type CharClass int

const (
	Consonant CharClass = iota
	Vowel
	Space
)

var AllCharClasses = []CharClass{Consonant, Vowel, Space}

func (cc CharClass) String() string {
	switch cc {
	case Space:
		return "Space"
	case Vowel:
		return "Vowel"
	case Consonant:
		return "Consonant"
	default:
		return "Unknown"
	}
}
```

It's still just 3 items: consonants, vowels, and spaces.

```go
const Vowels = "aáàäâæeéèëêiíïîoóôöœuüúý"

func BuildChain(r io.Reader) (Chain, error) {
	bf := bufio.NewReader(r)

	chain := make(Chain, len(AllCharClasses))

	var last CharClass = Space

	for {
		r, _, err := bf.ReadRune()
		if err != nil {
			if err == io.EOF {
				break
			}
			return nil, err
		}

		var next CharClass
		if r == ' ' {
			next = Space
		} else if unicode.IsLetter(r) {
			r = unicode.ToLower(r)
			if strings.ContainsRune(Vowels, r) {
				next = Vowel
			} else {
				next = Consonant
			}
		} else {
			continue
		}

		chain.Increment(last, next)
		last = next
	}

	return chain, nil
}
```

This is insufficient for anything real (e.g. I'm sure my list of vowels is
incorrect), but this is just a demonstration.

`BuildChain` reads one character (`rune` in Go's terminology) at a time,
determines it's type and feeds it into the chain under the previous character
type.

Now to put it all together:

```go
func main() {
	chain, err := BuildChain(os.Stdin)
	if err != nil {
		panic(err)
	}

	for _, cc := range AllCharClasses {
		link := chain[cc]
		if link == nil {
			continue
		}

		fmt.Printf("%s:\n", link.Value)

		total := float64(link.Sum())

		for _, childCC := range AllCharClasses {
			count := 0
			if child := link.Find(childCC); child != nil {
				count = child.Count
			}

			probability := float64(count) / total * 100
			fmt.Printf("%14s: %0.2f%% (%d)\n",
				childCC,
				probability,
				count)
		}

		fmt.Print("\n")
	}
}

func (l *Link) Sum() int {
	sum := 0
	for _, l := range l.Children {
		sum += l.Count
	}
	return sum
}
```

Finally, I can run it against all of War and Peace:

```
$ < war-and-peace.txt go run main.go 
Consonant:
     Consonant: 31.55% (493431)
         Vowel: 45.23% (707477)
         Space: 23.22% (363274)

Vowel:
     Consonant: 73.87% (698213)
         Vowel: 10.57% (99957)
         Space: 15.56% (147054)

Space:
     Consonant: 72.79% (372539)
         Vowel: 26.92% (137790)
         Space: 0.29% (1483)
```

Markov's point was that a letter depends on the previous letter. Which is shown
above, a consonant is likely to be followed by a vowel, even though grabbing a
random letter from the alphabet is more likely to produce a consonant.

The Markov chain code presented above is a simplified version of my [first
attempt](https://github.com/pboyd/markov/commit/b533f938d881596e786a764cce1dc8a88cac8b85).
I refined that version a bit and built a word generator. It would read some
text, build chains for letters and word lengths and then use those chains to
generate nonsense words:

```
t hebopas shéopatow icadsanca rb l inlisee enoh obe ndw aheaprpa nce lssover
en yhetrthie soh edgoany ermewha péndhesy sh evendat hau ssh ico ngowoul
```

The problem was that it had to read the text each time it ran. Reading an
entire book just to generate a lines of gibberish is kinda nuts. Clearly it
needed to store the chain on disk.

One approach to store a chain on disk is basically the same as the report
format above. For example, here's the Vowel/Consonant info in JSON (without
Space, just to keep it simple): 

```json
{
  "consonant": {
    "consonant": 751267,
    "vowel": 812915
  },
  "vowel": {
    "consonant": 812915,
    "vowel": 132309
  }
}
```

That's enough detail to recreate the chain, and writing it out and reading back
isn't too difficult.

The first issue with this approach is that the values are repeated. If there
are lots of values, or if they're especially large, the file size will be huge.

I wasn't planning to store the chain in a relational database, but if I were,
I'd have two tables:

```
values:
------------------
| ID | value     |
------------------
|  1 | consonant |
|  2 | vowel     |
------------------

value_link:
---------------------------------
| parent_id | child_id | count  |
---------------------------------
|         1 |        1 | 751267 |
|         1 |        2 | 812915 |
|         2 |        1 | 812915 |
|         2 |        2 | 132309 |
---------------------------------
```

If the IDs are sequential, that can be represented in JSON by parallel arrays:

```json
{
  "values": [
    "consonant",
    "vowel"
  ],
  "links": [
    [
      { "child": 0, "count": 751267 },
      { "child": 1, "count": 812915 }
    ],
    [
      { "child": 0, "count": 812915 },
      { "child": 1, "count": 132309 }
    ]
  ]
}
```

Now the value is only stored once, so it can be a giant blob a text if someone
wants. Since values are stored in an array, mapping an ID to a value can be
done in constant time. Unfortunately, going the other way and mapping a value
to an ID is slower, but that can be worked around.

I can re-implement the chain data structure this way too:

```go
type Chain struct {
	values []interface{}
	links  [][]ChildLink
}

type ChildLink struct {
	ID    int
	Count int
}
```

(Of course, that requires a different set of functions, which I won't go into
here, but that's essentially
[`MemoryChain`](https://github.com/pboyd/markov/blob/master/memory_chain.go) if
you want to see an implementation.)

My first attempt to write the chain to disk was to take an in-memory chain and
dump it into a binary file all at once. The format was the same concept as the
JSON format, with an "index" area that mapped IDs to values, and a "link" area
that kept relations between the IDs.

That worked, but the chain still had to exist in memory when it was built and
when it was used. Which means the size is limited by available memory, and
that's a shame. So I decided to make a chain that could be run entirely from
disk.

I wanted the disk chain to be equivalent to the memory chain. Ideally, the code
that uses it should be ignorant of how it's being stored. For instance, there
are few different ways to walk through the chain:

* Probabilistically: pick the next item randomly, but with weighted probability
* Iteratively: pick the next item in the order it was added
* Most likely: pick the next item by the highest probability

It would be terrible to implement disk-based and memory-based versions of all
those. Sounds like I need an interface:

```go
type Chain interface {
	Get(id int) (interface{}, error)
	Links(id int) ([]Link, error)
	Find(value interface{}) (id int, err error)
}

type WriteChain interface {
	Add(value interface{}) (id int, err error)
	Relate(parent, child int, delta int) error
}
```

As long as `MemoryChain` and `DiskChain` conform to that, the same code can
operate on both.

Markov chains are built from a stream of input items. Consequently, it's never
clear how many unique items will be encountered until after the chain has been
built. I still wanted the file to contain a value index that was separate from
the links. I was planning to store the index at the beginning of the file, so
the challenge was storing all the new values as they show up in the index,
without spilling over into the links.

I knew of a few ways to approach this:

1. When the index is full, create a new file with a bigger index and copy
   everything into it.
2. Use two files.
3. Just use SQLite
4. Chain several smaller index sections together.

(There must be better solutions, since databases do this kind of thing all the
time, but I don't know what they do.)

Resizing the index be quite slow. It also potentially wastes a lot of space.

Using two files would be simple to implement, since everything would be
appended to the file. But, I would still prefer a single file, since it's
easier to use.

Just using SQLite would have worked fine, but that would require C bindings,
and I was trying to keep it in pure Go.

Finally, I was left with splitting up the index into multiple chunks. It had
the advantage of not seeming awful. It reminded me of `malloc`, and how
appending to a file is actually quite similar to, say, `sbrk`. And SSDs are
increasingly common, which makes `seek` fairly fast.

I decided to pretend the file was a heap, and use file offsets like memory
addresses. Nothing would ever be unallocated, so new space would be allocated
by appending to the file. With those primitives in place, I could implement
data structures like I would elsewhere.

The links between values would be stored in a linked list, each node would
contain an ID, the number of times the value was encountered, and the offset
of the next node. Each ID would be the offset of a structure containing the
raw value and the offset of the head of the linked list.

It looked like this:

```
Item entry:
---------------------------------------------
| Value length | Value | Linked list offset |
---------------------------------------------

Link:
---------------------------------
| ID | Count | Next item offset |
---------------------------------
```

Mapping values to IDs needs to be done frequently, so quick lookups were
desirable. A hashmap would work, but that would require a bunch of empty
buckets which would bloat the file size. I settled on a binary search tree.

When I finally finished (and it took longer than I care to admit), I generated
a chain from the words in War and Peace. The in-memory version took a few
hundred milliseconds, the disk version took 13 minutes. I expected a slight
slow down, but 4 orders of magnitude?

I inspected it with the profiler and found that it spent all that time on
`Read` and `Write` system calls. This really shouldn't have been surprising.
Every level of that binary search tree required a `Seek` and `Read` call.
Reading a value required a `Seek`, then a `Read` for the value size and a
`Read` for the value itself. The linked list probably the worst, it required a
`Seek` and `Read` for every item, and every item had to be read.

I was able to speed it up a little. But it was clear pretty quickly that
nothing short of a redesign would help. It was just too many tiny I/O
operations. Hard disks are not RAM, no matter how much I want them to be.

It makes sense that larger reads and writes would incur less overhead and
therefore be faster. I never appreciated how much faster though. Here's a table
with the result of some benchmarks. Each test wrote and then read back a 1MB
file using a buffer of the given size (in bytes):

| Chunk size | Time |
|-----------:|:-----|
|8           |460ms |
|32          |103ms |
|64          |50m   |
|1k          |3.4ms |
|4k          |0.9ms |
|8k          |0.6ms |
|16k         |0.4ms |

My benchmarks were certainly not scientific, but they do show that it's much
faster to use larger chunk sizes than smaller ones. There must be a point where
a larger chunk size doesn't make a difference, but I should group as many I/O
operations together as I can.

To simplify things, I dropped the on disk index. A decent tree structure in
memory with hashed values would only require 32 bytes per entry, so 1 million
entries is only 30MB (probably a bit more in reality). That's small enough for
the smallest cloud computing instance, or a Raspberry Pi. I think a B-tree on
disk would do nicely, but that would be a large tangent on what's already too
large of a tangent. I do hope to correct this at some point (or, at least,
implement the tree in memory, since it still uses a `map` right now).

The links between items were the biggest problem. Finding the next item in the
chain requires reading every node in the linked list. Those can be in an array
(sort of) instead of a linked list. The only problem is that each item has
variable number of items, and I don't know how many. I ended up with a
structure that was similar to the linked list, except instead of individual
items it linked to a variable-size "bucket" of items:

```
List header:
--------------------------------------------
| bucket length | item size | first bucket |
--------------------------------------------

Each bucket:
--------------------------------
| next | item 1 | item 2 | ... |
--------------------------------
```

This allows a bunch of items to be read at one time, and it was much faster.
War and Peace only took 16s. Unfortunately, the file size was enormous (65MB
for a 3.5MB input file). The number of items per bucket turns out to be hugely
important. A large bucket size is fast, but wastes space with mostly empty
buckets. A small bucket size will produce a smaller file, but will be
slower because of the time taken to read all the extra buckets. I picked
something in the middle.

The other problem was the values themselves, they still required two read calls
to get the value: one for the size and one for the value itself. That can't be
avoided without fixed length values. Lists have the same problem, the list
header has to be read to tell where the bucket ends. I can't avoid that either.
But, at the very least, all of it can be combined into a single record:

```
---------------------------------------------------------------------
| value size | bucket length | item size | value ... | first bucket |
---------------------------------------------------------------------
```

That only requires two reads, one for the first three fields (which have a fixed
length), and one for the value and the first list bucket.

Even after all of that, building a chain on disk was still rather slow. I had
to compromise on the bucket size, which brought the time to process War and
Peace to 25s. I found that it's a lot faster to build the chain in memory and
then copy it disk. It certainly won't work for every dataset, but when it does
it's a lot faster. This also allows the first list bucket to contain the whole
list, since it knows the correct size from the memory chain.  After that War
and Peace took about 2s to generate on disk.

The disk chain fell a bit short in the end (it's still too slow, and it
requires an index in memory), but it seems like an alright Markov chain
implementation. The code is on [github](https://github.com/pboyd/markov), if
you're interested.
