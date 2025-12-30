---
title: Introduction to rewriting Git history
description: Small Git commits are great when working, but they aren't so great when looking at the history. This post examines the commands to make a clean Git history.
date: 2024-05-27
draft: false
type: post
---
I hope you had a chance to play the old Metroid games at least once. If not, find an SNES emulator (I promise it will be more fun than this blog post), or just imagine a 2D side-scroller with a character who shoots aliens and finds power-ups for her spacesuit (I could never figure out why the aliens had power-ups for a space suit they can't wear). During the occasional breaks in fighting, there would be a save point. It was a relief. That last section was hard, but it was over now, and I never had to do it again. I could always get back to the save point. Git commits are like that: they make a point you can always get back to. And, unlike Metroid, you can commit as often as you like. It's no wonder there are so many small commits:

```
$ git commit -a -m'first draft of fizzywigg'
$ git commit -a -m'fixes'
$ git commit -a -m'more fixes'
$ git commit -a -m'wip'
...
```

I take it for granted now, but making lots of little commits was one of the features that helped make Git so popular. Subversion, for instance, had a central server, and devs would typically commit to `trunk` which was shared with everyone. So we all held our commits until the code was stable.

But, while small commits are great, it's not very helpful to look back in the history and find hundreds of 2-line commits with monosyllabic commit messages where some portion turn out to be an unreleased development dead-end. Yes, merge commits do wonders for grouping these commits into logical chunks, but I think spending a few minutes to clean up the history before you merge makes for a history that is much easier to understand later.

Rewriting Git's history is not hard, but it's not obvious either. If a reviewer says, "can you squash these commits?" it isn't clear to the uninitiated that this means `git rebase -i`. So this post introduces the commands you need to produce a clean commit history that will be pleasant to use later. For the examples, I assume you're working on a feature branch that will be merged into a branch called `main`.

This will be most helpful if you experiment in your own feature branch. Nothing here is truly destructive, but some commands are hard to undo. So, if it helps you experiment with confidence, make a new branch first:
```
git switch -c tmp-branch
```

Play around on that temp branch, and if you screw it up, nothing is lost, just start over:
```
git reset --hard <original-branch-name>
```

You can see what code changed by diffing the two branches. If you like the result, run:
```
$ git switch <original-branch-name>
$ git reset --hard tmp-branch
```

## `git push --force`
The best time to rewrite history is **before** you push your feature branch. If you try to change any commits later plain `git push` won't work:

```
$ git push
To git:pboyd/repo.git
 ! [rejected]        goof -> goof (non-fast-forward)
error: failed to push some refs to 'git:pboyd/repo.git'
```

You can still push it, but you'll need to add `-f` (or `--force`):
```
git push -f
```

You may have been told not to force-push a branch. `--force` has earned its reputation, because it resets the remote branch to whatever is on your local copy, and you can delete someone else's code if you aren't careful. But `--force` on a remote _feature_ branch is usually OK, just make sure to coordinate with anyone else using it. And, of course, if that's only you, blast away.

## `git rebase`
You probably know rebase already. If not, rebasing is equivalent to stashing your changes, resetting your branch to some new point, and re-applying your changes. Effectively, this makes it appear that your changes were derived from somewhere else (in other words, a new base). I mostly use this to update code on a feature branch:

```
$ git fetch
$ git rebase origin/main
```

You may have conflicts when Git re-applies your commits. You have to fix the files in an editor, then:
```
$ git add <path/to/the/file>
$ git add <path/to/the/other/file>
$ git rebase --continue
```

If you want to start over after a conflict, run `git rebase --abort`.

## `git commit --amend`
`git commit --amend` causes Git to update the last commit instead of making a new one. I use this to fix typos or other small problems (CI errors, for instance). You could, conceivably, arrange your workflow around `--amend` and continually update a single commit.

You can use `--amend` like any other `git commit` invocation. For instance, to add all working changes to the most recent commit:
```
git commit -a --amend
```

`--amend` has a few options, which don't come up every day but are worth knowing about.

For instance, a common problem after rebasing upstream changes is that your timestamps are earlier than the commits that precede them. It bugs me on occasion, so I'll use `--amend --reset-author` to reset the timestamp:
```
git commit -a --amend --reset-author
```

As you'd expect from the name, `--reset-author` can also correct commits made from the wrong account.

`--no-edit` prevents the Git from launching an editor, which is handy when you don't want to change the commit message:
```
git commit -a --amend --no-edit
```

## `git rebase --interactive`

`git rebase --interactive` is not hard to use, but you may find it strange if you have not seen it before (at least, I found it strange at first). You run it like any other rebase, but stick `-i` (or `--interactive`) in the command:
```
git rebase -i origin/main
```

This opens your editor with a list of commits that looks like this:
```
pick 0d6a6c8 fixes
pick 49ce1ee more fixes
pick f677508 wip
```

This is, in fact, a script that rebase runs after you save and exit the editor. The default script adds every commit like a normal rebase would.

By the way, if you change your mind about the rebase, delete everything in the file, save, exit, and nothing will be done.

By changing the commands in the file you can do a great number of useful things. For instance, a really common use is to combine several commits into one:

```
pick 0d6a6c8 fixes
squash 49ce1ee more fixes
squash f677508 wip
```

I spelled it out above, but I normally use the short aliases for the commands:
```
pick 0d6a6c8 fixes
s 49ce1ee more fixes
s f677508 wip
```

`squash` is for when you want to include each commit's commit message. By default, the message for a squashed commit is a mechanical concatenation of the message from every included commit, which is a reasonable default but often a horrible commit message. You can change the message, but you can also use the first commit's message with `fixup`:
```
pick 0d6a6c8 fixes
f 49ce1ee more fixes
f f677508 wip
```

`git rebase` runs commands in the order you place them, so you can re-order commits however you like. But it's easy to create conflicts if a commit depends on changes that follow it. Likewise, it _only_ runs the commands you specify, so if you remove a commit from the list, it will be gone (consider setting `rebase.missingCommitsCheck` if that bugs you).

`reword` is another useful command. It allows you to update a commit message. I use this often, because I apparently have a chronic condition that causes typos.

`edit` is used to update the code in a previous commit. It's helpful sometimes, but I usually prefer to make another commit and do a `fixup` for simple changes (see below).

## `git rebase --autosquash`
Sometimes I want to make a change that logically belongs in an earlier commit, but I don't want to completely stop what I'm doing for an interactive rebase. The `--fixup` and `--squash` flags to `git commit` are helpful here:
```
git commit -a --fixup=HEAD~1
```

This creates a commit with an auto-generated message like "fixup! more fixes". That message is interpreted by an interactive rebase when auto squash is enabled and will cause the default command list to look like this:
```
pick 0d6a6c8 fixes
squash f5646ea squash! fixes
pick 49ce1ee more fixes
fixup 1efc224 fixup! more fixes
pick f677508 wip
```

Auto squash is disabled by default, so to get this behavior add `--autosquash` to rebase:
```
git rebase -i --autosquash origin/main
```

Or, if you prefer, set `rebase.autoSquash`:
```
git config --global rebase.autoSquash true
```

### `git reset`
Sometimes, the best thing to do is scrap the history and only keep the code. This removes the two most recent commits:
```
git reset HEAD~2
```

This doesn't touch the working directory, so no code has changed. It only resets the index and history. Afterward, you can rebuild your commit history (`git add -p` may be helpful).

This can be used to split up one big commit into several smaller ones. Or combine several small commits into logical blocks. This works well with the `break` and `edit` commands in `git rebase --interactive` if you want to redo an older commit but preserve what came after it.

## Bigger picture
The goal is to make the commit history mean something in the future. The point should not be to rewrite history to look like you wrote perfect code, but simply to communicate what changed effectively. Dead-ends (code that was reverted before it was deployed) can give a future developer wrong ideas about how the software worked. "WIP" and "doh!" commits are noise to slog through.

I should also note that there are diminishing returns with history rewrites. Squashing small commits is usually helpful. Splitting a big commit into logical chunks is sometimes helpful. But, as in all things, use judgment. Spending hours tweaking your commit history is probably not worth it and might make it harder to understand.
