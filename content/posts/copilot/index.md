---
title: "Github Copilot: A Preview of the Future"
type: post
date: 2023-04-16T00:00:00Z
expiryDate: 2025-12-30
image: copilot1.png
draft: false
---
I don't exactly hate new things, but I've generally had enough of what's new and shiny. This year's exciting new framework might be broken and abandoned next year. The hype cycle runs its course and all headline-grabbing technology goes the way of XML, ColdFusion and so many other things. That's why you'll find me on the sidelines, not that I don't try to new things, but I'm too old to rush. Young people excited by technology might even call me a curmudgeon, but how many 2 AM pages do you need to prefer what's trusty and dependable and boring?

So when I heard about [Copilot](https://github.com/features/copilot) I didn't jump at it. I didn't even slowly walk toward it. If anything, I eyed it suspiciously from a safe distance. But I was nudged from the sidelines this week, and even I must admit it's pretty great.

A brief example. I'm working on a project that uses [sqlc](https://sqlc.dev/) to generate the SQL-related boilerplate code. There's a `Makefile` in the project root to run `sqlc`, and I'm alternating between tweaking a SQL query and running tests. So all day I'm doing this:

```
~/dev/project/internal/somedir$ cd ../..
~/dev/project$ make sqlc
~/dev/project$ cd -
~/dev/project/internal/somedir$ go test
```

I eventually remembered to skip the `cd` commands with `make -C ../.. sqlc`. But even that's annoying, because some packages are two levels down, some are three. It isn't that big of a problem, but a little shell script aliased to `make` would make my day a bit brighter.

So I opened up `nvim` with the [Copilot extension](https://github.com/github/copilot.vim) and typed a comment (actually, Copilot tried to write the comment, but its suggestions were poor until the end of the line). Then it helpfully suggested the following:

{{< img
    src="copilot1.png"
    alt="copilot suggestion 1"
    sizes="(max-width: 430px) 300px, (max-width: 1000px) 400px, 960px"
    srcset="copilot1.png 960w, copilot1-400.png 400w, copilot1-300.png 300w" >}}

And, yeah, good enough. In fact, the script is basically done now, all that's left is to run `make`. As soon as I start the next line, Copilot knows where I'm headed:

{{< img
    src="copilot2.png"
    alt="copilot suggestion 2"
    sizes="(max-width: 430px) 300px, (max-width: 1000px) 400px, 960px"
    srcset="copilot2.png 960w, copilot2-400.png 400w, copilot2-300.png 300w" >}}

It correctly assumed that I wanted a comment about running `make`. Of course, guessing what happens after a comment that says "Now run make" isn't hard for it:

{{< img
    src="copilot3.png"
    alt="copilot suggestion 3"
    sizes="(max-width: 430px) 300px, (max-width: 1000px) 400px, 960px"
    srcset="copilot3.png 960w, copilot3-400.png 400w, copilot3-300.png 300w" >}}

That's the whole script. I could have written it, but I don't write _that_ many shell scripts, so it would take a few minutes of trial and error, a trip or two to `man sh`, and maybe even some light Googling. I can quibble over some of its choices, but the code works, my itch is scratched, and now I'm back to my real problem.

Writing that script would probably have taken me 15-20 minutes. Copilot did it in maybe one. The difference between `make sqlc` and `make -C ../.. sqlc` is so puny that spending even 15 minutes on it would likely be a net loss for productivity. In fact, I probably wouldn't have bothered without Copilot.

AI tools like Copilot are too new to understand the long-term implications, but the productivity win is too great to call it a flash in the pan. Something must come of it. What happens now? I don't know, I don't have a crystal ball. But I can give you my best guesses:
- At the risk of irresponsible extrapolation, we'll see larger-scale projects in the spirit of my shell script: things that were too costly before suddenly make sense.
- I hope I'm wrong, but tools like Copilot will be indispensable and more expensive. Computer programming is pricey talent, so what price will the market bear for an productivity boost that gives your company a competitive edge? I don't have the answer, but I know $100/year is laughably cheap.
- Your job may not be safe, but your career probably is. In particular, if your employer is content to keep output the same, they won't need the same number of programmers. But how many jobs does that apply to and why do you want to work there anyway? Companies that want to grow can now grow faster. Once it all shakes out, I think we'll see more software written by roughly the same number of programmers.
