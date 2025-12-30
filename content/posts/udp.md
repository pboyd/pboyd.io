---
title: "What is UDP?"
description: UDP may be overshadowed by TCP, but it's worth understanding UDP because someday it will be what you need.
date: 2024-08-20
draft: false
type: post
---
Imagine a holiday dinner with the Internet Protocol family: IP is at the head of the table, TCP is to the right, and UDP is to the left. ICMP is in the kitchen, SMTP couldn't make it (IMAP delivered the apology), and Uncle ARP sits quietly after the introductions. But otherwise, there's a lot of chatter (protocols, am I right?). TCP entertains everyone with the latest accomplishments of HTTP/2, just coming of age. IP listens with pride, knowing that the "TCP/IP Family" has a bright future with its undisputed scion: TCP. During a lull in the conversation, TCP looks over to UDP and asks with a smirk, "So, how's DNS?"

UDP bristled, "Quite well, no thanks to you. How's DNS over HTTPS?"

"Oh, you've heard about DoH. What a splendid little protocol it's becoming. Name resolution is such a trifle. How are you holding up with HTTP/3? That must be a strain for a protocol like you."

And, so it goes. Apparently, not even anthropomorphic networking protocols can have a civil family dinner. The rivalry between TCP and UDP has been fierce and one-sided. TCP is reliable. TCP runs the web. TCP runs e-mail. Meanwhile, UDP comes home after a piddling job with DNS to play video games.

Even so, during an (interesting!) career building software, you'll probably encounter a few good reasons to use UDP, but you won't recognize them unless you get to know this overshadowed little sibling.

## UDP defined
If you've heard anything about UDP, you've probably heard it described as connectionless and unreliable. That's true, but it's like describing Elon Musk as a wingless human: technically accurate, yet completely unhelpful. We usually define things by what they are, not what they aren't. So, what's UDP? Well, not much, it turns out. You can read [RFC 768](https://www.rfc-editor.org/rfc/rfc768.html) for yourself, but to summarize, UDP is layered on IP and adds port numbers:

```
 0      7 8     15 16    23 24    31
+--------+--------+--------+--------+
|     Source      |   Destination   |
|      Port       |      Port       |
+--------+--------+--------+--------+
|                 |                 |
|     Length      |    Checksum     |
+--------+--------+--------+--------+
|
|          data octets ...
+---------------- ...

     User Datagram Header Format
```

If you're developing a network stack, you should dig into the details of that checksum, but the rest of us can just remember that UDP adds ports to an IP packet. Of course, this is only a helpful definition if you know what IP is. Lucky for us, [RFC 791](https://www.rfc-editor.org/rfc/rfc791) has a wonderfully succinct description:

> The internet protocol implements two basic functions: addressing and fragmentation.

Fragmentation is a worthwhile topic for another time. Addressing is what we need to understand right now. It's so easy to take this for granted today that I fear you will tune me out, but please bear with me: hosts connected on IP networks have addresses, and if you know another host's address, you can send it a _datagram_. It's amazing, actually. It works all over the world. We usually say _packet_ today, but _datagram_ is a nice word. Think of it like an old-time telegram for data on a packet-switched network. IP is concerned about your datagram's payload size, but besides that, it doesn't care what you send. IP only delivers datagrams to other hosts.

But IP doesn't actually try very hard to deliver your datagram. In fact, it makes no guarantees. Your datagram could be lost, sent to the wrong address, or mangled beyond recognition. Even if it does arrive, nothing may be there to receive it, and if you sent multiple messages, they may be out of order. IP doesn't care. Networks aren't reliable, and IP won't let you pretend that they are.

Lobbing off datagrams and hoping for the best may be good enough for IP, but humans usually need stronger guarantees than that. If these were telegrams instead of datagrams, we might layer in a human protocol, like, "Please confirm that you received this message at once." At the risk of over-simplifying, TCP is a more formal and complete extension of that idea. That makes TCP reliable, but it comes with trade-offs. Here are a few:

- TCP has connections, which ensure both sides are ready to communicate. But the handshake adds latency. And the client-server model it requires is sometimes too strict (the server must listen first, and only the client can initiate the connection).
- TCP re-transmits lost packets, but it means that every data packet has to be acknowledged.
- TCP delivers packets in order, but now we need sequence numbers on every packet. It also causes the so-called queuing problem: high-priority packets stuck in a queue behind a re-transmission of an low-priority packet.

The trade-offs are often acceptable, but sometimes they aren't, and when they aren't, you may wish you could send IP datagrams. The problem is that IP datagrams go to hosts, not programs on a host. Multiple programs attempting to communicate by raw IP datagrams would be a mess: programs would have to recognize and filter messages intended for another program. UDP, if you remember, adds ports to IP datagrams. So now, instead of listening for datagrams on an IP address, a program can listen for datagrams on a port. You could say it's a protocol for delivering IP datagrams to users (or, at least, user-level programs) instead of hosts. Or, if you like, the User Datagram Protocol.

## What's it for?
This has been more theoretical than I usually like, so let me wrap up with some of my favorite reasons to use UDP, with some real-world examples:

- Live data: when the most recent reading is the only one that matters, you don't want to wait for TCP to re-transmit an old packet. For instance, the latest view of a live camera feed or the state of the world in a video game.
- Performance: TCP is reasonably fast, but it puts reliability above low latency or high throughput. For the absolute best performance, UDP is the way to go. This is why HTTP/3 is over UDP (via QUIC). And why most networked video games use UDP.
- Application layer adds reliability: sometimes you don't need TCP's reliability because the application layer provides it already. This is the case for WireGuard. As a VPN, it has an entire IP stack anyway. There's nothing lost by using UDP because it wraps another unreliable IP packet. Applications that need reliable communication can still use TCP: IP->UDP->IP->TCP
- Especially unreliable networks: The flip side of UDP's lack of guarantees is that it also has no penalties for failures. If the recipient is frequently missing, it's fine. There's no connection to maintain and no sequence numbers to keep in sync. WireGuard, again, benefits from this. You can open an SSH connection over WireGuard at home, pick it up from a tethered cell phone connection in the car, and keep it open on the public Wi-Fi at your local coffee shop. WireGuard tunnels are over UDP, so there's no connection to re-establish.
