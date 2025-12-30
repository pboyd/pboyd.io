---
title: "Text Encoding: The Thing You Were Trying to Avoid"
date: 2020-07-08T11:15:00Z
draft: false
type: post
discussions:
- url: https://www.reddit.com/r/programming/comments/hnflyh/text_encoding_that_thing_you_were_trying_to_avoid/
  site: /r/programming
- url: https://lobste.rs/s/cskbgh/text_encoding_thing_you_were_trying_avoid
  site: lobste.rs
---

Programmers tend to treat text encoding like the office bore. You weren't
planning on a 2-hour conversation about your co-worker's lawnmower today?
Well too bad, because it's happening now. Text encoding is much the same, it's
always around, but we'd rather avoid it. From time to time it pops over anyway
to mess up your day and fill you in about the latest nuance between a code
point and a character, or something equally dull. I used to pay about as much
attention as that thrilling tale of a recent blade height adjustment.

But I've been tinkering with text encoding lately, and it's not really so
awful. In fact, text encoding can be interesting. Not quite fun, let's be
honest, but definitely interesting. UTF-8, in particular, is elegant and well
designed. If nothing else, text encoding is everywhere and you can't avoid it
forever, so we might as well try to understand it.

## ASCII and its extensions

ASCII is an obsolete 1960s-era character set. Or, at least, it would be
obsolete if it weren't extended multiple times. ASCII only has 128 characters.
Just enough for English, and some teletype control characters. ASCII characters
fit in one byte, so the "encoding" is simple: store the character code in a
single byte. This is terribly convenient. Bytes are characters, characters are
bytes, and no one talks about code points.

As an added bonus, since computer memory comes in 8-bit bytes, not 7, there's a
leftover bit. It could be used to extend ASCII with another 128 characters.
After all, there are people in the world who don't speak English and would like
to see their own language on the screen.

These extended ASCII character sets were eventually standardized as ISO-8859.
ISO-8859-1 covers English and most Western European languages. ISO-8859-5
covers Cyrillic. ISO-8859-6 is Arabic. You get the idea.

This system at least allowed languages other than English to be represented.
But you had to pick a character set and stick with it. You couldn't just throw
a Cyrillic or Greek letter into your English document. And this system
would never allow enough characters for Chinese, Japanese, or Korean.

## Unicode and UCS-2

Unicode is an effort to define one character set for all the world's
characters. When Unicode was first being planned it was clear that it was going
to be huge. One byte was obviously not enough, so a second byte was added to
allow for 65,536 code points. That probably seemed like enough at the time.
That two-byte encoding is UCS-2.

It's a simple scheme, to encode it you write the Unicode value in a 16-bit
word:

```c
#include <stdio.h>

int main(int argc, char **argv) {
    short str[] = {
        'H', 'e', 'l', 'l', 'o', ' ',
        'w', 'o', 'r', 'l', 'd', 0x203d, '\n',
    };
    fwrite(str, 2, 13, stdout);
    return 0;
}
```

Run that, and you'll probably see this:

```
$ cc main.c && ./a.out | hd
00000000  48 00 65 00 6c 00 6c 00  6f 00 20 00 77 00 6f 00  |H.e.l.l.o. .w.o.|
00000010  72 00 6c 00 64 00 3d 20  0a 00                    |r.l.d.= ..|
0000001a
```

Intel architectures use a little-endian byte order so I get `48 00`. If you run
it on an IBM mainframe or an old Motorola processor or any other big-endian
machine, the bytes would be reversed: `00 48`.

If text always stays on the same computer this is fine, but if you want to send
text to another computer it has to know that you meant U+203D (‽) and not
U+3D20 (㴠). The convention is to write U+FEFF at the beginning of a document.
This is the "byte order mark". A decoder knows if it sees `FF FE` to use
little-endian, and if it sees `FE FF` to use big-endian.

Of course, if you want to make a general UCS-2 encoded or decoder you have to
write all your code twice:

```go
switch d.byteOrder {
	case bigEndian:
		return (rune(buf[0]) << 8) | rune(buf[1]), nil
	case littleEndian:
		return (rune(buf[1]) << 8) | rune(buf[0]), nil
	default:
		return 0, errors.New("unknown byte order")
}
```

## UTF-16

Unfortunately for UCS-2, Unicode outgrew two bytes. Sure, Unicode characters
through U+FFFF (the "Basic Multilingual Plane") can be encoded in UCS-2, and
that's enough sometimes. But if you want more Chinese characters, or Klingon, or the fancy
Emojis you can't use UCS-2.

In UTF-16 each code point takes either two or four bytes. The two-byte version
is the same as UCS-2. The four-byte version contains a "high surrogate" in the
first two bytes and a "low surrogate" in the last two bytes. The surrogates can be
combined into a code point value. In case you're wondering, the high and low
surrogate ranges are defined in Unicode so they don't conflict with any other
character.

Let's look at the UTF-16BE encoding for U+1F407 (🐇):

```
D8 3D DC 07
```

In binary that's:

```
11011000 00111101 11011100 00000111
```

The code point value is in the lower 10 bits of each surrogate pair, so we can apply a bit mask:

```
  11011000 00111101 11011100 00000111
& 00000011 11111111 00000011 11111111
  ----------------- -----------------
  00000000 00111101 00000000 00000111
```

The decoder takes that result, shifts and `OR`s and adds `0x10000` to get the
code point value.

```go
cp := rune(highSurrogate & 0x3ff) << 10
cp |= rune(lowSurrogate & 0x3ff)
cp |= 0x10000
```

That's a basic a UTF-16 decoder. Naturally, it inherited the big-endian and
little-endian variants from UCS-2, along with the necessary byte order mark.

UTF-16 does the job. But it feels like what you get when you chip away every
objection until you find a compromise everyone can barely tolerate.

## UTF-32

ASCII and UCS-2 are fixed width, which is easy to work with. But if you want to
hold the whole range of Unicode with a fixed width you need four bytes, and
that is UTF-32. Every code point, 4 bytes.

UTF-32 will be faster for some operations, so as a trade-off of space for time
it has its place. But as a general-purpose encoding, it's wasteful. For
instance, ASCII characters are common in the real world, but each one wastes 25
bits in UTF-32.

It's even worse than that. The largest assigned Unicode code point is U+10FFFF,
which requires 21 bits. Consequently, there are at least 11 unused bits in every
code point. That's right, there's always at least one completely unused byte in
every UTF-32 encoded code point.

Just like the other multi-byte encodings, UTF-32 comes in big-endian and
little-endian versions as well. One nice thing about UTF-32's wasted space is
that you don't usually need a byte order mark.  Let's look at U+1F407 (🐇)
again:

```
UTF-32LE: 07 F4 01 00
UTF-32BE: 00 01 F4 07
```

There's a zero byte on one side or the other, so the decoder can find the byte
order for any code point.

**Correction:** *[caarg98](https://www.reddit.com/u/caarg98) [pointed out on Reddit](https://www.reddit.com/r/programming/comments/hnflyh/text_encoding_that_thing_you_were_trying_to_avoid/fxgdfmn/?context=3) that this is not correct. A code point like U+10100 will begin and end with a zero byte in UTF-32 (`00 01 01 00`), so this isn't a perfect way to determine the byte order. It does still work when only the beginning or end of the encoded code point is a zero byte.*

## UTF-8

UTF-8 is another variable-length encoding. Each code point takes one to four
bytes. ASCII characters (that is, Unicode code points below U+80) take just one
byte. Every other byte in UTF-8 will have its high bit set (`b & 0x80 != 0`).

For a multi-byte code point, the total number of bytes is encoded in the first
byte, as the number of 1 bits before the first zero. Convert it to binary and
it's easy to see:

* `110xxxxx`: 2 bytes
* `1110xxxx`: 3 bytes
* `11110xxx`: 4 bytes

The bits after the length bits make up the beginning of the code point. Subsequent
bytes always begin with a `1` and a `0`, followed by six bits of the value.
Here's the full scheme:

```
1 byte: 0xxxxxxx
2 byte: 110xxxxx 10xxxxxx
3 byte: 1110xxxx 10xxxxxx 10xxxxxx
4 byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
```

If you count the `x`s on the four-byte version you'll find 21. Exactly enough
to store the highest Unicode code point, 0x10FFFF. Here are some examples:

```
U+D8 (Ø): 11000011 10011000
U+A733 (ꜳ): 11101010 10011100 10110011
U+1F600 (😀): 11110000 10011111 10011000 10000000
```

After the first byte, a decoder has to mask the low six bits of each byte, then
shift it onto the code point value.

Here's a [Go decoder](https://gist.github.com/pboyd/06c089eeba85fb46c108e42e42f8f035).
That's silly, of course, since Go has excellent support for UTF-8. Its built-in
strings are already UTF-8. Which shouldn't be any wonder, since Ken Thompson
designed [UTF-8](https://www.cl.cam.ac.uk/~mgk25/ucs/utf-8-history.txt) with
Rob Pike and then they both worked on [Go](https://golang.org/doc/faq#history).

## So what?

Everyone has mostly settled on UTF-8 in the past few years. But I think it's
worth examining this decision. Let's recap:

- A fixed width would be nice, but 1-byte and 2-byte encodings can't encode all of Unicode.
- A 3-byte encoding would be impractical.
- A 4-byte encoding (UCS-4 / UTF-32) is outrageously wasteful outside a few special cases.

So fixed-width encodings are out. The only options left are either UTF-8 or
UTF-16. Let's compare.

### UTF-8 is backwards compatibility

Did you notice how every ASCII characters only take one byte? That means that
ASCII documents are already UTF-8. That actually covers a lot of real-world text.
The English front page of Wikipedia, for instance, 99% of characters are ASCII.
The French version is still 98% ASCII, and even the Japanese version is 91% ASCII.

UTF-8 also never has a NULL byte. Which means this actually works on my computer:

```c
#include <stdio.h>

int main(int argc, char **argv) {
    printf("Hello, 🌎!\n");
    return 0;
}
```

If that doesn't work, this definitely will:

```c
#include <stdio.h>

int main(int argc, char **argv) {
    printf("Hello, \xf0\x9f\x8c\x8e!\n");
    return 0;
}
```

Trying the same trick with UTF-16 and it won't get past the first character:

```c
#include <stdio.h>

int main(int argc, char **argv) {
    printf("\x48\x00\x65\x00\x6c\x00\x6c\x00\x6f\x00\x0a\x00");
    return 0;
}
```

It prints an "H" then quits. The `\x00` is interpreted as the end of the string.

In fact, much of the C standard library (`strcmp`, `strlen`) works fine with UTF-8.
Not so with UTF-16, you can't embed the encoded bytes in 8-bit numbers. Your
best bet is probably to convert it wide chars and use the wide versions of those
functions.

### UTF-8 is simpler

UTF-16's byte order handling complicates everything. Here's a [simple C
program](https://github.com/pboyd/ustring/blob/master/examples/utf16_print.c)
that decodes UTF-16 and prints the code point.  The only thing complicated
about that program is handling the byte order mark. Everything you want to do
with a UTF-16 string has to consider the byte order.

But UTF-8 is read one byte. In fact, there's no other way to do it.
Consequently, there is no byte order to worry about. Here's the [UTF-8
version](https://github.com/pboyd/ustring/blob/master/examples/utf8_print.c) of
the earlier program.

### UTF-8 can be synchronized

A decoder can always tell where a code point starts in UTF-8. This is not the
case for UTF-16.

Let's say you want to fill your home with classic literature and decide to
start with the WiFi:

```bash
while true ; do cat alice-in-wonderland.txt anna-karenina.txt art-of-war.txt | iconv -t UTF-16 ; done | nc -u 224.0.0.1 4567
```

`iconv` converts the text to UTF-16 and `nc` sends it via UDP multicast to all
hosts on your home network (presumably over WiFi, because otherwise what's the
point?). On some other host on your network you can read it:

```bash
nc -lu 224.0.0.1 4567
```

Or just grab a sample:

```bash
nc -lu 224.0.0.1 4567 | hd -n 48
```

Anna Karenina uses the Cyrillic alphabet, and the Art of War is in ancient
Chinese. There's no telling what you'll get. Here's one sample:

```
00000000  74 00 6f 00 20 00 61 00  20 00 68 00 69 00 67 00  |t.o. .a. .h.i.g.|
00000010  68 00 20 00 67 00 6c 00  61 00 73 00 73 00 20 00  |h. .g.l.a.s.s. .|
00000020  74 00 61 00 62 00 6c 00  65 00 20 00 61 00 6e 00  |t.a.b.l.e. .a.n.|
00000030
```

Looks like we got Alice in Wonderland that time, since `to` is more likely than
`琀漀`. But we didn't tell `iconv` explicitly what byte order to use and
there's nothing in the data to tell us.

```
00000000  0a 00 0a 00 14 04 3e 04  3a 04 42 04 3e 04 40 04  |......>.:.B.>.@.|
00000010  20 00 3f 04 3e 04 34 04  42 04 32 04 35 04 40 04  | .?.>.4.B.2.5.@.|
00000020  34 04 38 04 3b 04 20 00  41 04 32 04 3e 04 38 04  |4.8.;. .A.2.>.8.|
00000030
```

This begins with two new lines and `Д`, so we're probably in Anna Karenina.

UTF-16 over UDP works better than I thought it would. I suspect that even-sized
packet sizes keep the characters lined up. If it lost a byte everything would
shift and we wouldn't be able to tell where a code point begins.

Contrast this with a sampling of the UTF-8 version of the same stream:

```
00000000  b0 2c 20 d1 81 20 d0 be  d1 82 d0 b2 d1 80 d0 b0  |., .. ..........|
00000010  d1 89 d0 b5 d0 bd d0 b8  d0 b5 d0 bc 20 d0 b3 d0  |............ ...|
00000020  bb d1 8f d0 b4 d1 8f 20  d0 bd d0 b0 20 d0 b2 d1  |....... .... ...|
00000030
```

The first byte is `0xb0`, which is `0b10110000`. Since it starts with `0b10`,
we know it's not the first byte in a sequence and we can skip it. Same with the
next two bytes `0x2x` and `0x20` both begin with `0b10`.

The fourth byte, however, is `0xd1`, or `0b11010001` which is the first byte of
a two-byte sequence for `с` U+0441. We did miss a code point, but there was no
ambiguity and after that, we're in sync.

## Code

Thanks for taking the time to read this. If you're interested I put some text
encoding code up on github:

* [Go encoder/decoders](https://github.com/pboyd/unirecode) for ASCII, UCS-2, UTF-8, UTF-16 and UTF-32
* [C utilities](https://github.com/pboyd/ustring) for UTF-8 and UTF-16.

There are better tools than these, probably with fewer bugs. But since I was
just tinkering these are unconcerned with the real world. Which makes them
fairly simple projects and hopefully easy to read.
