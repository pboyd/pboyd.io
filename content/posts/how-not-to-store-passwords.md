---
title: "How Not to Store Passwords"
date: 2019-11-22
draft: false
type: post
description: "Like it or not, your users depend on you to protect their passwords. Here's a list of the worst things you can do."
discussions:
- url: https://www.reddit.com/r/programming/comments/e03trw/how_not_to_store_passwords/
  site: /r/programming
- url: https://www.reddit.com/r/programming/comments/gkda0i/how_not_to_store_passwords/
  site: /r/programming (again)
related:
- /posts/securing-a-linux-vm
---

Here's a fun list to look through: [Dumb Password
Rules](https://github.com/dumb-password-rules/dumb-password-rules). Most of the
rules seem arbitrary, like only allowing digits, but some hint at deeper
problems. For instance, preventing single-quotes. They aren't inserting
passwords into a database without a SQL placeholder, right? Nearly every site
on that list has a needlessly short maximum password size. If they're storing
passwords correctly, there's no need for this. This post will go through a few
bad ways to store a password and you can see what I mean.

## Plain text

The absolute simplest way to store a password in a database is to just store it
in plain text. Here's an
[example](https://github.com/pboyd/dumbpasswds/blob/master/application/plaintext.py),
it's probably nothing surprising. Here's the code to create an account:

```python
def create_account(self, cursor, username, password):
    if len(password) < 8:
        raise PasswordTooShort()

    if len(password) > 16:
        raise PasswordTooLong()

    cursor.execute("SELECT count(*) FROM plaintext WHERE username=%s", (username,))
    result = cursor.fetchone()
    if result[0] > 0:
        raise UsernameTaken()

    cursor.execute("INSERT INTO plaintext (username, password) VALUES (%s, %s)", (username, password))
```

Nothing complicated here, just a few basic checks and an `INSERT`. My database
column has a max size of 16 characters, which I had enforce to prevent the user
getting an ugly 500 error[^1].

Of course, this is terrible. Even if the site in question doesn't have
anything of real value, the passwords themselves can be valuable. A lot of
people use the same password for everything. When a sites asks for a password,
they put in _their_ password. The password they gave you is the same password
they've used for their email and bank account. Don't feel too special, they
probably give it out to anyone that asks for the WiFi password.

I thought everyone knew not to store passwords in plain text, but I was wrong.
[Have I Been Pwned](https://haveibeenpwned.com/PwnedWebsites) is another fun
list to look through. There are plenty of sites that leaked plain text
passwords. From [big
names](https://www.troyhunt.com/what-do-sony-and-yahoo-have-in-common/) that
you'd think would know better[^2].

## Encryption

So you've decided not to store your passwords in plain text. Good for you. If
you think about it, a password is kind of like a secret message, so why not encrypt it?
[The
code](https://github.com/pboyd/dumbpasswds/blob/master/application/encrypted.py)
is similar to the plain text version, except it calls a
[library](https://pypi.org/project/PyNaCl/) to encrypt and decrypt the
password.

```python
key = b'this is a super-duper secret key'

def encrypt_password(self, plaintext):
    box = nacl.secret.SecretBox(self.key)
    return box.encrypt(bytes(plaintext, 'utf-8')).hex()

def decrypt_password(self, ciphertext):
    box = nacl.secret.SecretBox(self.key)
    bc = bytes.fromhex(ciphertext)
    return box.decrypt(bc).decode('utf-8')
```

This is an improvement over plain text, and it would probably be difficult for
an attacker without the key to decrypt a password. But, depending on how the
encrypted passwords were obtained, the attacker may have the key.

Anyway, the mere existence of the key complicates things. Now we have to figure
out how to store it, and who can have it, how the software that needs the key
will get it, and a bunch of other problems besides. My little demo side-stepped
all of this and just hard-coded the key. Somehow, though, the key has to be
available in the login code, and that makes it possible for an attacker to get
it.

Another problem is that the length of the password determines the length of the
encrypted text. Which means we still have to enforce a max password size to
avoid overflowing the database column. But also the encrypted text gives away
the length of the password, or a least an approximate length. This makes it
much easier to brute-force leaked passwords.

I worked on a (now dead) project that encrypted passwords like this, and I
thought it was a unique "innovation". In fact, I thought it was so rare that I
wasn't going to include it here. But I was wrong, [Adobe did the exact same
thing](https://nakedsecurity.sophos.com/2013/11/04/anatomy-of-a-password-disaster-adobes-giant-sized-cryptographic-blunder/).

## Hashes

Cryptographic hash functions allow one person to prove they know a secret
without having to say what the secret is. These functions work by deriving a
value from the password. There is no algorithm to get the input text back from
the resulting hash. Which is exactly what you want for a password, since you
don't need to know the password, you just need to know if it's correct. In
fact, it's a liability if you do know the password, so hash functions make
sense.

There are a few hashing algorithms to choose from, and most programming
languages provide implementations of the popular ones. My demo app has
implementations for
[MD5](https://github.com/pboyd/dumbpasswds/blob/master/application/md5.py) and
[SHA256](https://github.com/pboyd/dumbpasswds/blob/master/application/sha256.py).
MD5 is largely broken, so it shouldn't be used any more. The SHA-2 family is
still considered secure.

Here's the code to check a password:

```python
def login(self, cursor, username, password):
    cursor.execute("SELECT password FROM sha256 WHERE username=%s", (username,))
    result = cursor.fetchone()
    if result == None:
        raise BadLogin()

    if result[0] != self.hash_password(password):
        raise BadLogin()

def hash_password(self, password):
    return hashlib.sha256(bytes(password, 'utf-8')).hexdigest()
```

It retrieves the hash from the database and compares it to a hash of the
password from user. If the hashes match, the password is correct.

Hash functions always produce the same size output, so (within reason) there's
no need to limit the size of a password.

Unfortunately, a hash by itself is not enough. It's pretty common that several
accounts will have the same bad passwords (you didn't think you were the only
one who used `superman`, did you?) These stick out in password dumps:

```
 username |                             password                             
----------+------------------------------------------------------------------
 bob      | 5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8
 sally    | 5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8
 jim      | c43d1b57a27277d2846f6058d32cd3882885656612b48907f1e0fb93c8370e2b
```

Bob and Sally both used `password`. If an attacker cracks one password, every
account with that password has been cracked. There are [lists of common
passwords](https://github.com/cracklib/cracklib/blob/master/words/files/cracklib/words.bz2)
on the internet. All an attacker has to do is hash the passwords in the list
and find the accounts that match in the dump. It won't crack every password,
but it will probably crack enough, and in very little time.

Cryptographic hashes are fast to compute on normal hardware. A GPU can make the
work go faster. Some of the algorithms are used in digital currency mining,
which has prompted the development of custom hardware (ASICs) to compute them,
and that's faster still. So a brute-force attack that tries every combination
is actually becoming reasonable, even against strong passwords. If computing
the hashes it too much work, attackers can also download a rainbow table, which
is a pre-computed list of hashed password.

It's been known for a long time that plain hashes for passwords is pretty dumb,
but there are still frequent dumps of passwords using nothing more than a basic
hash. [LinkedIn](https://haveibeenpwned.com/PwnedWebsites#LinkedIn), for
example, lost SHA1 hashes. The infamous [Ashley Madison
breech](https://haveibeenpwned.com/PwnedWebsites#AshleyMadison) contained MD5
password hashes (in addition to `bcrypt`).

## Salted Hashes

Since an attacker can download a rainbow table of standard hashes, what if you
just added a little extra text to every password? So store hashes of
`MyCoolSite{password}`, then attackers would need a unique rainbow table just
for `MyCoolSite`. Better still, give every password it's own bit of text, then
an attacker needs a new rainbow table for every password. And duplicate
passwords still produce unique hashes. That bit of text is a "salt".

Here's some code to generate a salted hash:

```python
def hash_password(self, password, salt=None):
    if salt == None:
        salt = secrets.token_bytes(16)

    salted_password = salt + bytes(password, 'utf-8')
    return salt.hex() + hashlib.sha256(salted_password).hexdigest()
```

A random salt is chosen and prepended to the password before it's hashed. The
salt is needed to verify the password, and it isn't a secret, so it needs to be
stored. It doesn't matter how the salt is stored, I prepended it to the hash,
but any way is fine as long as it can be retrieved.

To check a salted password, recalculate the hash with the same salt and see if
the hashes match:

```python
def check_password(self, hashed, password):
    salt = bytes.fromhex(hashed[0:32])
    new_hashed = self.hash_password(password, salt)
    return new_hashed == hashed
```

Salted hashes are a big improvement. But the speed that hashes can be
calculated makes brute-force attacks against even salted passwords [quite
reasonable](https://www.troyhunt.com/data-breaches-vbulletin-and-weak/).

## Key Derivation Functions

Salted hashes would be fine if they just took longer to brute-force. And
that's the principle behind key derivation functions (KDFs). They require more
compute time (and some require memory also), which requires an attacker to
spend real money to crack them.

There are a few algorithms to choose from. PBKDF2 and bcrypt may be
brute-forced before too long. scrypt and argon2 look like they'll be with us
longer. There are implementations for every major programming language.

Password storage is usually not a selling point, so I understand that it's a
tempting corner to cut, but it's a risk. And it seems like an unnecessary one,
when the difference between dumb password storage and good password storage is
just a matter of calling the right library. 

All the code used in this post is on [github](https://github.com/pboyd/dumbpasswds).

[^1]: I'm using Postgres, which raises an error. Other databases, such as old versions of MySQL, silently truncate the value. Wild conjecture of course, but that sounds suspiciously like what happens [here](https://github.com/dumb-password-rules/dumb-password-rules#best-buy).
[^2]: [Also Sony in 2012](http://fse2012.inria.fr/SLIDES/67.pdf). Seems like these two groups should have been talking to each other.
