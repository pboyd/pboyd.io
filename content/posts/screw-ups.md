---
title: "The day I wiped a production database table"
date: 2022-06-03
draft: false
type: post
discussions:
- url: https://www.reddit.com/r/programming/comments/v3ymsq/the_day_i_wiped_a_production_database_table/
  site: /r/programming
- url: https://news.ycombinator.com/item?id=31628142
  site: Hacker News
- url: https://lobste.rs/s/bikgmx/day_i_wiped_production_database_table
  site: lobste.rs
---
It seems everyone has a story like this, but I'll give you mine anyway. I was 6-months into my first real developer job, trying to fix a bug. Our application would sometimes insert rows with an invalid "foreign key" (we used MySQL with MyISAM, which didn't have foreign key constraints--but it had an ID for another table anyway). Of course, the bug was only seen in production, so I had a production MySQL shell open to see the bad rows.

I was trying to reproduce it in dev. My process was to try something, then look at my dev database in a second MySQL shell. Except the table would get cluttered, so I started running `TRUNCATE tablename` between trials to delete all the rows. You can probably guess what happened next.

At some point, I find it strange that my command history doesn't have the `TRUNCATE` command anymore. But no problem, I simply type it again and hit `<enter>`. It took a few moments to realize what I'd done. It's peculiar, but at some deep level, all fear must be the same. I only remember a sinking feeling as blood rushed from my head to my extremities. As far as my psyche was concerned, I didn't need to think anymore, that blood was needed to either run or fight.

I calmed down a bit and was sure I'd be fired, but I wasn't. My manager was not happy, but someone had to clean it up, and that was going to be me. We had a department meeting to consider our options. It could have been called the "let's talk about how Paul screwed up today" meeting. Necessary, but it sucked. I took it in stride though, as I mentally prepared to take my wife and infant son to pick out the cardboard box we'd soon be living in.

In the end, it wasn't so bad. The table was basically a list of jobs that needed to run at specific times--not irreplaceable. In fact, it could be rebuilt, and we even had a script to do just that. It was restored within a few hours. I kept my job, my manager suggested forms of alcohol that would be most appropriate for that evening, and I swore on a stack of O'Reilly books to close production MySQL shells promptly forever after.

The end.

Except that shouldn't have been the end. I had never heard the phrase "blameless postmortem", but that was the time for it. To be sure, I did a stupid thing, but that was only part of the problem.

I learned to stop using the write-enabled database account. But, as far as I know, no one ever asked why a junior developer had access to a production database. I probably did need read access, but why write access? And if I did need write access, did I really need permission for a destructive command like `TRUNCATE`?

We were also unable to restore the table from backup. The database admin could restore the entire database from the last snapshot, but he didn't have a procedure to restore a single table. We would have lost over 12 hours of more important data.

In hindsight, the shameful part of this story is that we left it at "operator error" and didn't dig deeper.
