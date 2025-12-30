---
title: "Limits of Programmer Productivity"
subtitle: "A lesson from Fred Brooks on development environments"
date: 2023-06-16
draft: false
type: post
description: "Fred Brooks published The Mythical Man-Month in 1974. As technology goes, it's ancient. Yet it still has lessons to teach us."
image: mythical-man-month-horizontal.jpg
image_caption: "Mythical Man Month cover"
lastmod: 2023-07-01
discussions:
- url: https://news.ycombinator.com/item?id=36361857
  site: Hacker News
- url: https://lobste.rs/s/io6fyl/limits_programmer_productivity_lesson
  site: lobste.rs
---
{{< img src="mythical-man-month.jpg" alt="Mythical Man Month cover" width=308 height=450 >}}

Fred Brooks published _The Mythical Man-Month_ in 1974, describing the lessons he learned leading IBM's OS/360 project during the 1960s. As technology goes, it's ancient. Consider the workflow for a "debugging run":

> We centralized all our machines and tape library and set up a professional and experienced machine-room team to run them. To maximize scarce S/360 time, we ran all debugging runs in batch on whichever system was free and appropriate. We tried for four shots per day (two-and-one-half-hour turnaround) and demanded four-hour turnaround.

Apparently, the typical programmer's day involved a lot of waiting around for an operator to run your program after you prepared your punch cards. This is obviously inefficient, and Brooks has a suggestion to improve it:

> The whole fifteen-man sort team, for example, would be given a system for a four-to-six hour block. It was up to them to schedule themselves on it.
> ...
> For each man on such a team, ten shots in a six-hour block are far more productive than ten shots spaced three hours apart, because sustained concentration reduces thinking time.

I am not advocating block scheduling computer time[^1]. But, if we dig a little deeper, he's really saying we need to increase the number of "shots taken," which is as true today as it was then. The number of shots determines the limit of programmer productivity, so to go faster we have to decrease the time for each one.

This lesson is not only old, but it almost seems too obvious to write about. And yet I know of a team who (right now, today) deploys code to a shared dev server to check almost everything. There's only one server, and it's the only way to realistically run the code. It takes 10 minutes to deploy, and they had better work fast because the next deployment will be soon. They missed this lesson, and I doubt they're alone.

Unfortunately, building a comfortable and fast development environment is a surprising amount of work. I started a personal [project](https://github.com/pboyd/nomenclator) (it's nothing special, I am trying to shift my career toward independent contracting, so I need something in GitHub to prove that I build [more](https://github.com/pboyd/robovac) [than](https://github.com/pboyd/robovac) [peculiar](https://github.com/pboyd/malloc) [toys](https://github.com/pboyd/sum)), and two weeks of evenings all I have managed to build is one primitive API endpoint. But I can run it quickly and easily, and I expect the groundwork pays off in with more productivity later. And hopefully, for my next project, I can copy it as a starting point.

[^1]: Block scheduling could make a comeback, as it begins to make sense when there's scarcity. High GPU prices create similar incentives already, and who can say what time on the first practical quantum computers will cost.
