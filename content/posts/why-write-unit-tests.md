---
title: "A simple case for unit tests"
date: 2020-02-24T18:00:00-05:00
expiryDate: 2025-12-30
draft: false
type: post
---

I learned recently that the word _playwright_ is unrelated to _write_. It is,
in fact, derived from _wrought_. A play is not written, it's beaten into shape.
In that vein, _codewright_ ought to be a word, because I've never written
software from top to bottom, it's hammered and stretched until it's right.[^1]

My personal process usually goes like this:

0. Figure out what the next bit of code should be
1. Write it
2. Run it
3. Check the result
4. Failed? Fix and go back to #2.
5. Succeeded? Repeat from the top.

Yes, it's infinite. It never ends, I just commit periodically.

Notice the tight loop between steps #3 and #5? That's the critical path to
optimize[^2]. Running and checking the code varies a lot. For me it's usually
restarting a web server and checking the output on a few requests. But, however
it looks, it takes time and it's error-prone.

Unit tests are simply code that runs and checks your other code. Ideally, they
do it quickly and completely. And they should still work the next time you need
them. It's just pre-computing what you can before that loop to avoid
re-checking at every iteration. Tests won't initiate a golden age for your
company's development department, they will bring neither fame nor fortune. In
fact, sometimes they do more harm than good. But when they make sense, write
them. Frankly, you don't have time not to.

[^1]: In fact, can we replace all the construction metaphors with theatre metaphors? It would be a whole lot more fun. Programmers and playwrights both create scripts for others to run, so I think it works.
[^2]: Step #1 is really where all the time goes, but it's not so easily optimized.
