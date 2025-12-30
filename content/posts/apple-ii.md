---
title: "Back to basics with the Apple II"
date: 2023-01-01
draft: false
type: post
tags:
- apple-ii
discussions:
- url: https://www.reddit.com/r/programming/comments/1019z2m/back_to_basics_with_the_apple_ii/
  site: /r/programming
- url: https://www.reddit.com/r/apple2/comments/101q2xu/back_to_basics_with_the_apple_ii/
  site: /r/apple2
related:
- /posts/useless-program
---
I have a confession: I don't think very much about memory when I'm programming. I know it's there, of course, but only in an abstract way. I'm far removed from the details. If a program manages memory particularly badly, then I have to get involved with the details. But, even then, the job is to get the usage back down to something reasonable so I can move on to something useful.

I should mention that I work mostly in Go, I would think about memory more if I worked on embedded systems or even programmed more C or C++. But I write web services in Go and my variables and structs might as well be stored in AWS Pixie Dust for all it matters.

This is probably how it should be. Programmer time is better spent thinking about product features than memory addresses. I am, after all, employed to make products, not software (even if they happen to be software products). So I can't spend too much time on details that are better left to machines.

But I still feel that I've lost something. A computer is a delightful device full of possibility and RAM. Something to play with. Sometimes I want to tinker and simply interact with it on some deeper level. But modern programming seems less like play and more like trying to coerce an omnipresent bureaucracy. I know why it has to be this way, but it's not a fun way to spend a weekend.

## Going deeper

Before I look too far, I should mention that we can look a little deeper without leaving Go (not a lot deeper, mind you--but it's a start). For instance,  Go will happily hand you a chunk of memory to play with:

```go
buf := make([]byte, 0x10)
```

Go isn't so happy about the next part (I'd call it a bit grumpy even), but you can take an address from that buffer and treat it like some other type:

```go
p := (*uint16)(unsafe.Pointer(&buf[0]))
*p = 0x1234
```
[Try it yourself, if you want](https://go.dev/play/p/bAXU6QSkgQl)

This works because (even in Go) memory is still just memory. As far as the hardware is concerned there's no such thing as a type. C hides that fact a little, Go hides it a bit more, by the time you move up the stack to JavaScript or Python I'll forgive you for believing any kind of strange thing about how your variables are physically stored.

This example uses `unsafe.Pointer`, which you're discouraged from using by seemingly everyone. Even the package name is a warning. I'm not suggesting you start using `unsafe.Pointer` everywhere, but consider for a second that the "safe" (i.e. typed) pointer is the oddity. A pointer is simply memory that holds the address of another memory location, it does not intrinsically have a type.

I took the idea behind this example a bit further and wrote a primitive version of [`malloc`](https://github.com/pboyd/malloc). It's fun to see the memory dumps as the blocks coalesce when the memory is freed, but otherwise, this isn't capturing the wonder of computing, because it's still very disconnected from the actual hardware.

## Back to basics

What I'm after probably doesn't exist in modern computers, so I will try old hardware (or emulated old hardware, anyway). Specifically, the Apple II.[^1]

I have never used an Apple II before, but I've been experimenting with it using [MicroM8](https://paleotronic.com/software/microm8/). It's very unusual compared to everything I've used before. Nothing is obvious when running it, but it's simple enough that the basics are easily learned. One difference from modern computers that I was not expecting is the prevalence of memory addresses.

In fact, I imagine every Apple II user needed to memorize a few memory addresses. They're useful, after all. For instance, you can clear the screen with `CALL -936` or enter the `MONITOR` program with `CALL -151`. Those are the signed 16-bit decimal equivalents of the memory addresses `0xFC58` and `0xFF69`, `CALL` appears to be nothing but a front-end for the jump instruction.

Poking around in Apple DOS is fun (you know, the copyright date on Apple DOS 3.3 was 40 years ago to the day as I write this), but to fully understand a computer there's no substitute for Assembly.  So let's look at "Hello, World!" in 6502 Assembly.

```
        ORG $300
Start   JSR $FC58    ; Call the clear screen routine.

        LDY MSG      ; Load message length in Y.
                     ; Y will count down to 0.

        LDX #$1      ; Load array index in X.
                     ; Start at 1 to skip the length byte.

Loop    LDA MSG,X    ; Copy the character from msg+X to the
        STA $6FF,X   ; screen, starting at $700.
        INX          ; Go to the next character.
        DEY          ; Reduce our counter by 1.
        BEQ End      ; Is our counter 0? End now.
        JMP Loop     ; It's not 0, keep going.
End     RTS

MSG     STR "Hello, world!" ; Message to write. First byte is the length.
```

The assembled machine code will be loaded into memory at the `ORG` (short for origin) address. Picking a good `ORG` seems to have been quite the task. Short programs like this one are fine at `0x300`. But if your program grows in size and hits the screen buffer at `0x400` your program will start filling up the screen. A catastrophic failure, but at least a noticeable one. It's enough to make me wonder if I could run a program directly from the screen buffer, and that's exactly the kind of fun I was hoping to find.

The user can load the program wherever they want, but since our assembler calculates that `MSG` is at address `0x316` there's no telling what it will print if it's loaded to another address.[^2]

The first thing our program does is clear the screen. It uses the same procedure we saw earlier (`CALL -936`), except this time it uses the unsigned hexadecimal address (`JSR $FC58`). There isn't a symbolic name for this, you simply jump to that location and hope you're not running on some funky machine where that's not the clear screen routine.

We could have called `0xFDED` to print a character on the screen. But I like that I can write directly to the text buffer at `0x700`, so I'll do that.

This program is simple enough that it only needs the 6502's registers. If I needed another variable, I could find an unused address for it. Because the Apple II's memory is mapped to physical chips, I could, in theory, remove the cover to find the chip which held my new variable. Now contrast that with my day job where I sometimes forget where in the world my code runs.

---

I've been off work for the past week and spent much of it writing a dynamic memory allocator for the Apple II. Take a look if such things interest you: [a2malloc](https://github.com/pboyd/a2malloc).

A special thanks to the CoRecursive podcast, where their [latest episode's](https://corecursive.com/doomed-to-fail-with-burger-becky/) guest, [Rebecca Heineman](https://twitter.com/BurgerBecky), had the excellent suggestion to try programming an Apple II.

[^1]:  In case you're wondering, this isn't nostalgia. The Apple II was in decline by the time I was born. The first computer I remember well was an IBM PS/2. That one I'm nostalgic about. I get nostalgic about the Web in the 90s or video games on Windows 95. But the Apple II was simply before my time. This is, in fact, the far worse cliche of harkening back to a supposed golden age which probably wasn't so grand anyway.
[^2]: Relocatable code was possible, but I don't know how common it was.
