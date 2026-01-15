---
date: '2026-01-11T13:27:20-05:00'
draft: true
title: 'Coming to terms with AI Coding Tools'
---

I love writing code. My professional titles have almost always been _Software
Developer_ or _Software Engineer_, but I always considered it a pity that I
couldn't be a plain-old _Programmer_. I know why: I'm paid to build software,
not write code. Software can be sold, code cannot. But it's the code, not the
software, that I love.

Don't misunderstand me. I like it when people want to use the software I work
on, but most software is terrible and I can't count on anyone liking it. It's
conceived in a drunken collaboration between Product and Marketing and joyously
received at birth. But its first steps are so awkward that no one can imagine
it running, and before long even its, now sober, parents stop expecting much.
Lacking the resolve to snuff it in the cradle, but not wanting it to corrupt
the more promising software either, they hand it to a developer like me to see
it through adolescence. Who knows? Maybe it can still grow up to be a
responsible Product (or, if they dare to dream big, a Solution). So I tend my
charge and make sure it grows, amusing myself with its algorithms and patching
its bugs. I don't love it, but no one else does either. It's just software.

The idea of a tool that promises to handle the code and let me focus on the
software sounded awful. Those beautiful puzzles and algorithms would now be
implementation details handled by the machine. All that would be left for me is
to write specs and check that the implementation is correct. All software, no
code.

I loathed Cursor as I installed it. I thought about my 12-year-old self
wondering how they made my games work. If I had just gone outside that day
instead of poking around at a BASIC interpreter, then maybe I wouldn't be in
this situation. But, no matter, remaining relevant (or, at least, employed)
meant learning the incantations of this cursed IDE.

I started by telling it to do the entire task I was working on at the time, and
I felt smug when I rejected its attempt. Apparently, it wasn't _that_
intelligent. I re-started small, telling it to implement specific functions. It
did better, but I learned that I had to explain what I wanted in great detail.
Such great detail, in fact, that it would have been easier to write the
functions myself, and so I did. But when the function was complete and I was
dreading writing a unit test, I remembered that I could tell Cursor to do it
instead. I had to remind it to verify that its tests actually run, but I could
eventually prod it into writing complete and working tests. They were
uninspiring, but sufficient. I was less a vibe-coder, and more a mule driver.

Outside of bossing around an AI code bot, I spent the rest of my time in Cursor
fighting 20+ years of VIM muscle memory (yes, I found VI-mode, it was
almost--but not quite--passable). After a brief diversion with
[Avante][avante], I landed on Claude Code. It was perfect. I coded in nvim and
it waited patiently out of my way in its tmux pane until I needed it to write
tests.

[avante]: https://github.com/yetone/avante.nvim

I found some other uses for it too. Because, while I love writing code, I don't
love writing _all_ code. I've already mentioned unit tests, but there's also
refactoring (e.g. "make this `int64` an `int32` and fix everywhere that uses
it") and mindlessly extending established patterns (e.g. "add one more param to
this endpoint"). And all sorts of other tasks that aren't even programming
(e.g. "squash the commits on this branch and summarize the code in the commit
message", "create a Jira ticket for this FIXME comment"). The parts of
programming I want to do, I'll continue to do as long as I can. But the
scaffolding and admin tasks around it? Let Claude figure it out.

That's where I am right now, solidly in the AI-assisted programmer camp. It
hasn't turned me into a drone that merely tells Claude to load a ticket and
implement it. It hasn't given me programming superpowers either. But it does
let me focus on the parts of my job that I enjoy. I like figuring out
algorithms and discovering the reason for a bug, and I still can.

Can this last? I can only speculate. Some executives would like to replace
engineering departments with a handful of AI-powered product owners, and maybe
they'll try it. But with today's tools, I don't see how it can work for very
long. Someone still needs to understand the code and the problem space deeply
enough to drive the tool properly. It's easy to generate a program you don't
understand, but it's much harder to fix a program you don't understand. At
least, that's what I tell myself.
