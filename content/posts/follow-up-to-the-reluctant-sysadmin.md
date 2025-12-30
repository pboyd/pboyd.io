---
title: "Follow up to the Reluctant Sysadmin's Guide"
date: 2023-08-06T00:00:00Z
draft: false
type: post
---
Hacker News had a [lot to say](https://news.ycombinator.com/item?id=36934052) about my [article](https://pboyd.io/posts/securing-a-linux-vm/) on securing a server. Oddly, it was one of my more popular articles, but the comments on HN were nearly all negative (2 of 30 top-level comments were positive, and the rest were neutral or critical). But I like being told I'm wrong. Not at first, of course--I am human, after all. But looking back, I nearly always learn something, even if I disagree. So this post is just me responding to that comment thread.

Let me say, first of all, that this was a great comment thread and worth reading. Critical of me, yes, but remarkably civil. Everyone mostly stuck to facts and had specific critiques.

I won't respond to everything, but I have tried to hit the high points. I trimmed the comments a bit, but there are links to the unabridged versions with their context. If you feel I left something out or didn't fairly represent a point of view, email me, and I'll try to fix it.

## Guides like this shouldn't exist
>  There's a reason guides like this are a dime a dozen - there is no way to generalize server configuration this broadly. -- [gazby](https://news.ycombinator.com/item?id=36935042)

>  This notion of security is stale. Real security is far more complex than this, requiring automated provisioning and logging. -- [acumenical](https://news.ycombinator.com/item?id=36940688)

> But really the idea of being successful at anything while also having no knowledge of it is kind of a farcical contradiction.{{< br >}}
> It’s like saying, look, I just want to build a rocket engine. Tell me how without all the physics mumbo jumbo. -- [user3939382](https://news.ycombinator.com/item?id=36941394)

My goal was a 20-30 minute procedure that someone without much experience could apply to get some basic system-level security. No, it isn't possible to cover system security in a blog post, but I can tell someone how to turn off password logins on SSH, get port 22 off the Internet, and point toward a few other things to consider. That's all I was trying to do.

I meant this article for people who don't often think about security but want a game server, a blog, or to run that web app they've been working on. There are plenty of "pets" in the world, and that's not always bad. I can't seriously suggest anything else for a Minecraft server for a handful of friends. CIS Benchmarks and STIGs are fine, but they aren't something a typical hobbyist will pick up and use, and much of it would be irrelevant anyway. There's clearly a demand for more approachable content, and I don't think it's unreasonable for it to exist, even if my particular attempt was no good.

Admittedly, I should have set the scope and the expectations better in the title and introduction. I shouldn't imply that a blog post can cover all of system security.

## If it should exist, it should not be written by you
> Perhaps one ought not take sysadmin advice from a blog post with a first sentence that reads "I’m not a sysadmin, and I don’t want to be". -- [gazby](https://news.ycombinator.com/item?id=36935042)

> How can one make a guide to assist people to be successful in something they don't want to do in the first place? -- [AdieuToLogic](https://news.ycombinator.com/item?id=36935042)

I also taught my kids to take out the trash. Trash collection is not a passion of mine, but I think I effectively shared the lesson. If everyone only wrote about things they liked to do, then I don't know how we would have product manuals, or write-ups of city council meetings.

But I don't actually deny the accusation. I don't claim to be an expert in security. I wrote this post after redoing my blog server and finding myself disappointed with the available information. So I combined what I knew from experience and what I could find and wrote a blog post. I thought it had some value, and I still think it might.

## This stuff is mostly irrelevant
>  Meh, just do it like me get hardened image and container. Deploy stuff as a gold image without elevated permissions and or container. Then just make sure everything is behind a proxy or intelligent load balancer that restricts any crazy input. -- [Sparkyte](https://news.ycombinator.com/item?id=36935183)

>  I actually disagree with most of this. I think that, for servers, it's best to stay as close to the "cattle, not pets" model as reasonably possible. Servers should be set up and maintained with automated tooling and rarely connected to manually, preferably only to debug issues. Most of the things in here are gimmicky one-offs that don't meaningfully increase security. -- [ufmace](https://news.ycombinator.com/item?id=36937949)

> You don't need to configure SSH access because SSM session manager exists, which also makes the WireGuard setup superfluous, too. -- [\_el](https://news.ycombinator.com/item?id=36938431)

> if you're focused on getting software out the door your best bet is not to touch any of this stuff and deploy on a platform where configuring the Linux distro is not your responsibility. i.e. k8s or AWS ECS -- [kbar13](https://news.ycombinator.com/item?id=36939381)

Related to this, but hard to capture in a single quote, is the debate from the comment thread on whether SSH was even necessary. If you have AWS SSM, something similar, or even the cloud provider's web UI, why bother with SSH? Since SSH featured prominently in the article, I'm including it here.

I won't try to argue against SSM. It is probably a better option than SSH if you're on AWS (ditto for other providers with similar tools), and I should have mentioned it. But not everyone is on AWS. I mostly use Linode, for instance, which doesn't have anything similar (except console access in a web UI, which I don't consider a suitable alternative). 

And, yes, you can avoid server maintenance with k8s, ECS, and many other tools. But a server is sometimes unavoidable, and server maintenance is sometimes more desirable than the alternatives. For instance, I ran my blog on GKE for a while, but that was overkill and comparatively expensive (it was mostly an excuse to play with k8s). I could host this site with S3 and CloudFront, but I don't want even that amount of vendor lock-in. And my inexpensive VPS works fine. In some sense, it is a pet, though I prefer to think of it as a herd of one (there's no redundancy, but I think the world can manage without my blog for a couple of hours if I need to fix it).

## Missing context
> It's weird to begin such an exercise without stating what the point of "the server" is supposed to be. Is it a ... web server? Interactive unix logins for developers? Mail relay? What does it do? This is the key point of the analysis because "securing" a server consists in making it incapable of doing anything not in the set of things it is meant to do. -- [jeffbee](https://news.ycombinator.com/item?id=36934509)

> securing from what? this thing is pointless mid-90ies advise without a threat-model. -- [DyslexicAtheist](https://news.ycombinator.com/item?id=36936046)

> Everyone is parroting the same thing over and over again, but no one is going into the whys. Why do this, what's the benefit, how will it thwart this or that type of attack. -- [lofaszvanitt](https://news.ycombinator.com/item?id=36943177)

As mentioned earlier, my goal was to document a procedure, not explain things. It may have been helpful to have more "whys," but I figured most people who would want this post wouldn't care. Perhaps that was wrong.

An early draft of that post actually had much more to say about identifying threats, but I cut most of it to keep the length more reasonable. That was a mistake. I see that now.

## Root vs. user accounts
> the only thing that locking the root account gets you is assurance that if you ever bork the user you created in this guide (or sudo functionality as a whole) you'll have no way to recover without booting into another environment. -- [gazby](https://news.ycombinator.com/item?id=36935042)

> > You should not log in directly as root.
>
>  Why not? -- [jesprenj](https://news.ycombinator.com/item?id=36936845)

> Don't bother setting up a user account, use a public key authorized SSH session as root to do everything. -- [ufmace](https://news.ycombinator.com/item?id=36937949)

My philosophy (which I still don't think is controversial) is to assume that every previous layer of defense is compromised and secure accordingly. That means more layers are generally better. If an attacker exploits the application layer and gets a shell, that's a bad day, no matter what. But it would be a slightly better day if the compromised account didn't have access to much. That's the main point of a separate root account.

Of course, back to my notable omission of threat identification, it depends on what the attacker wants. If the attacker wants to borrow the host's network access, then any account will do. You can thwart, or at least slow down, other kinds of attacks by requiring a root account. For instance, the docroot on my web server is only writable by root, so merely compromising my user account isn't enough to deface the site.

The other reason for not allowing direct root logins is for auditing. By default, Debian logs who ran what with sudo in `/var/log/auth.log`. So we can see "Jimmy logged in as root" instead of merely that someone logged in as root. Of course, that is irrelevant if you only have one user, so we're back to threat assessments again.

## Umask
> > We want a umask of 077, 
>
> No we don't. This creates problems with many packages. -- [lazyant](https://news.ycombinator.com/item?id=36951457)

> I don't see much point in things like Wireguard or this umask thing. -- [ufmace](https://news.ycombinator.com/item?id=36937949)

>  I like the changing of the default umask, although it probably shouldn't be 077. -- [mmsc](https://news.ycombinator.com/item?id=36934555)

That is the first I have heard about problems with packages created by setting `umask` to `077`. Perhaps someone can enlighten me.

Anyway, the point of changing the `umask` is to reduce accidental exposure because someone forgot to run `chmod`. You can either default to loose permissions and tighten them or default to tight permissions and loosen them. I prefer to loosen them (on a server, at least--my desktop is `022`, and I don't plan on changing it).

If someone exploits your application code and gets a shell running as `www-data` (or similar), they can't access the clutter in the user's home directory. I know, "cattle, not pets," but if you have a pet, the `umask` probably matters.

As for `077` vs. `027`, there's almost no difference on a default Debian install since every user gets their own primary group. `077` seemed ever-so-slightly more advantageous, and a procedural guide has to pick something.

## WireGuard
> Fwiw, this guide also suggests setting up a wg connection which is no better than ssh, and probably worse in some ways. -- [onlypositive](https://news.ycombinator.com/item?id=36951833)

> I don't see much point in things like Wireguard or this umask thing. -- [ufmac](https://news.ycombinator.com/item?id=36937949)

>  I don't get why a wireguard vpn to connect to ssh would be any better than just ssh directly (assuming reasonable ssh config) -- [bawolff](https://news.ycombinator.com/item?id=36940835)

> You don't need to configure SSH access because SSM session manager exists, which also makes the WireGuard setup superfluous, too. -- [\_el](https://news.ycombinator.com/item?id=36938431)

The point is to get SSH off of the open Internet. Again, this adds another hurdle for an attacker to get through. WireGuard is pretty tough, but even if it weren't, SSH over WireGuard is still stronger than SSH alone. Anyone who manages to gain access to the WireGuard network still has to contend with SSH.

There are certainly other options. The original article mentioned allowing an IP range, possibly the IP of a bastion host. As mentioned earlier, SSM would be fine, but not everyone is on AWS. WireGuard works for me, and I think it would work for other people too. That's why I suggested it.

## acl
> Is acl needed over, say, chown? -- [mmsc](https://news.ycombinator.com/item?id=36934555)

>  No, there's no need to use `setfacl` over `chown/chmod` in the author's example. -- [aesh2Xa1](https://news.ycombinator.com/item?id=36934979)

> Also installing acl just to use setfacl bothered me. -- [acumenical](https://news.ycombinator.com/item?id=36940688)

I agree with this one. The idea was to make the SSH keys only writable by root with read-only access for only one user. Yes, there are simpler options.

## Other Omissions
>  Real security is far more complex than this, requiring automated provisioning and logging. -- [acumenical](https://news.ycombinator.com/item?id=36940688)

>  Also configure fail2ban and enable it for ssh. -- [msravi](https://news.ycombinator.com/item?id=36945144)

>  No Fail2ban? -- [optimalsolver](https://news.ycombinator.com/item?id=36939896)

> Run lynis and linpeas!!!
>
> Also, setup auditd and rsyslog forwarding. Backup anything important. -- [badrabbit](https://news.ycombinator.com/item?id=36939170)

>  No mention of SSH certificates? -- [g4zj](https://news.ycombinator.com/item?id=36939170)

I can't cover everything related to system security in a blog post. So the question is, are any of these topics critical? Or, at least, more important than what I did cover?

- Automated provisioning - I touched on this in the article, but I don't think I can do much more in a blog post where automated provisioning isn't even the main point.
- Logging - This was a clear miss in the article. At least backing up logs is necessary for audits. Alerts based on those logs would be more beneficial than much of what was covered.
- `fail2ban` - I considered a section on `fail2ban` but ultimately decided against it. I didn't cover any applications, so the only service that could benefit from `fail2ban` is SSH. I didn't see any reason to use `fail2ban` after locking down port 22.
- `lynis` and `linpeas` - I had not heard of these before, but they look interesting.
- Backups - This isn't primarily related to security. But it is a factor, and I should have mentioned it.
- SSH certificates - If I had more than a handful of users logging into a machine, I would consider SSH certificates. But I don't, and I doubt most people reading this guide will either.

## What now?

Here are my takeaways:
- The scope of the article was too broad, and I shouldn't have implied that it was suitable for everyone.
- Identifying threats needed a much bigger place. It was probably the most important thing.
- I should have mentioned that SSM (or something similar) would let someone avoid nearly this whole article. 
- The reasons behind the steps are often more important than the steps themselves, and I shouldn't have skipped those.
- Logging and alerts, which I skipped, are more important than some of what I did cover.
- `setfacl` was unnecessarily complicated.

I still think this guide can be helpful, but I want to change a few things. I am still figuring out what form that will take. Whatever I decide to do, I intend to keep the original around, but possibly with a link to an updated guide.
