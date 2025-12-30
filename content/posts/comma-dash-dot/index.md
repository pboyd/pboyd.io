---
title: "The regex [,-.]"
date: 2022-05-11
lastmod: 2023-07-01
draft: false
type: post
description: "\"[,-.]\" matches a comma, a dash or a period, but it shouldn't work."
image: code.png
image_caption: "[,-.]"
discussions:
- url: https://www.reddit.com/r/programming/comments/un7yft/the_regex/
  site: /r/programming
- url: https://lobste.rs/s/h5nhrq/regex
  site: lobste.rs
- url: https://www.reddit.com/r/programming/comments/vqh8lq/the_regex_comma_dash_dot/
  site: /r/programming (again)
---

{{< autoimg src="code.png" alt="[,-.]" >}}

I stumbled on this regex recently: `\d{2}[,-.]\d{2}`.

The intention is clear enough: match two sets of two digits separated by a comma, a dash, or a period. Of course, it shouldn't work. Dashes in character classes are special because they're used for ranges (like `[a-z]` to match lower-case ASCII letters). If you want `-` in a character class you put it at the beginning, or the end, never the middle. So this should be `[-,.]` not `[,-.]`.

I assumed that `[,-.]`  was a typo and it wouldn't match `-`, but I couldn't find a bug. In fact, it works fine, you can try it yourself:

```bash
$ perl -E 'say "ok" if "12-34" =~ /\d{2}[,-.]\d{2}/'
ok
```

Try a few variations with other characters, if you want. It won't match `-` unless it's at the beginning or end of the character class, except for `[,-.]`:

```bash
$ perl -E 'say "ok" if "12-34" =~ /\d{2}[*-,]\d{2}/'
$ perl -E 'say "ok" if "12-34" =~ /\d{2}[a-z]\d{2}/'
$ perl -E 'say "ok" if "12-34" =~ /\d{2}[-*,]\d{2}/'
ok
$ perl -E 'say "ok" if "12-34" =~ /\d{2}[-a-z]\d{2}/'
ok
$ perl -E 'say "ok" if "12-34" =~ /\d{2}[,-.]\d{2}/'
ok
```

What's going on? Well, if you haven't figured it out already, the comma, the dash, and the period are right next to each other in ASCII:

```sh
$ man ascii
...
       054   44    2C    ,
       055   45    2D    -
       056   46    2E    .
...
```

So grabbing all characters from `,` to `.` also includes `-` and nothing else. `[,-.]` is the only possible character class with a `-` in the middle that only matches `-`.

I can't tell if the author was being clever or if it was a particularly lucky typo. Either way, I will continue putting `-` at the beginning: `[-,.]`. But if you feel the need to send someone down a rabbit trail `[,-.]` is an option for you.
