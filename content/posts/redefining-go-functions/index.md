---
date: 2026-02-05T05:53:26-05:00
draft: false
title: Redefining Go Functions
type: post
---
I once wrote a [Perl subroutine][1] that, when called, would wrap its caller in a subroutine that cached the return value based on the input (a memoizer). That much was potentially useful, but it also inserted a copy of itself into the caller, so that _its_ caller would be memoized too. A well-placed call to `aggressively_memoize` could back-propagate to a whole codebase spreading functional purity like a virus. The resulting program would be fast, and yet largely static.

That was possible because Perl, like many interpreted languages, allows functions to be rewritten:

```Perl
no strict 'refs';
*{$caller} = $new_sub;
```

Overuse of this feature has given it a terrible reputation, earning it the derisive nickname "monkey patching". Spend a couple hours debugging why your program prints the wrong time only to discover you have a mock time implementation implanted by some distant dependency and you'll hate it too. But these days I program mostly in Go where such nonsense isn't possible. Right?

Well no, not exactly. True, Go doesn't offer this as a language feature. But a CPU executes instructions from memory, and we modify memory all the time. Did Go fundamentally change that? I don't think so.

Let's say I would prefer Alan Jackson's sense of time over whatever reality `time.Now` cares to remind me of. Which is to say, I want this function to replace `time.Now`:

```Go
func myTimeNow() time.Time {
	return time.Date(2026, 1, 30, 17, 0, 0, 0, time.FixedZone("Somewhere", -5))
}
```

The first thing we need is the address of the real `time.Now`. That's easiest to do using `reflect`:

```Go
func main() {
	addr := reflect.ValueOf(time.Now).Pointer()
	fmt.Printf("0x%x\n", addr)
}
```

Run this program and you'll get an address:

```
$ go build -o main && ./main
0x498b60
```

Now disassemble the program and note the memory address in the second column:
```
$ go tool objdump -s time.Now main | head -3
TEXT time.Now(SB) /opt/go1.25.5/src/time/time.go
  time.go:1343          0x498b60                493b6610                CMPQ SP, 0x10(R14)
  time.go:1343          0x498b64                0f8684000000            JBE 0x498bee
```

Function pointers in Go actually point to the entry point of the function.

We don't know the length of the function, but we can make a guess that it's at least 8 bytes and get a slice to it:

```
func main() {
	addr := reflect.ValueOf(time.Now).Pointer()
	buf := unsafe.Slice((*byte)(unsafe.Pointer(addr)), 8)
	spew.Dump(buf)
}
```

```
$ go build -o main && ./main
([]uint8) (len=8 cap=8) {
 00000000  49 3b 66 10 0f 86 84 00                           |I;f.....|
}
```

`49 3b 66 10` matches the first instruction from the disassembled output.

If we overwrite that with a jump/branch instruction to our replacement function
we should be all set. On x86 that looks like:

```Go
func main() {
	addr := reflect.ValueOf(time.Now).Pointer()
	buf := unsafe.Slice((*byte)(unsafe.Pointer(addr)), 8)

	buf[0] = 0xe9                                // JMP
	src := addr + 5                              // Where to jump from
	dest := reflect.ValueOf(myTimeNow).Pointer() // Where to jump to
	binary.LittleEndian.PutUint32(buf[1:], uint32(int32(dest-src)))

	fmt.Println(time.Now().Format(time.Kitchen))
}
```

Now run it, and:

```
unexpected fault address 0x499400
fatal error: fault
[signal SIGSEGV: segmentation violation code=0x2 addr=0x499400 pc=0x4a3c9c]
```

Of course it segfaults. Letting a program modify its own code is dangerous, and
protected memory has been standard for decades. But it's not hard to get
around, we just need to change the permissions on that memory page. On Unix
systems we do that with `mprotect(2)`. The start address has to be page
aligned, so a little helper function is in order:

```
func mprotect(addr uintptr, length int, flags int) error {
	pageStart := addr &^ (uintptr(syscall.Getpagesize()) - 1)
	region := unsafe.Slice((*byte)(unsafe.Pointer(pageStart)), length)
	return syscall.Mprotect(region, flags)
}
```

Now we use that to allow writes to the function, and restore the protection
afterwards:

```Go
func main() {
	addr := reflect.ValueOf(time.Now).Pointer()
	buf := unsafe.Slice((*byte)(unsafe.Pointer(addr)), 8)

	mprotect(addr, len(buf), syscall.PROT_READ|syscall.PROT_WRITE|syscall.PROT_EXEC)

	buf[0] = 0xe9                                // JMP
	src := addr + 5                              // Where to jump from
	dest := reflect.ValueOf(myTimeNow).Pointer() // Where to jump to
	binary.LittleEndian.PutUint32(buf[1:], uint32(int32(dest-src)))

	mprotect(addr, len(buf), syscall.PROT_READ|syscall.PROT_EXEC)

	fmt.Println(time.Now().Format(time.Kitchen))
}
```

```
$ go build -o main && ./main
5:00PM
```

_Viola!_ It's 5PM. It's always 5PM.

[Full source][2]

If you're on ARM64, you'll need [this version][3]. Aside from different instructions, the ARM version also requires clearing the instruction cache. (I've only tested the ARM64 version on a Raspberry Pi 4 running Linux. I _think_ it will work for Darwin on Apple silicon but I don't have the hardware to test it--if you try it, let me know how it goes.)

If you're on Windows, you won't have `mprotect`. Supposedly [`VirtualProtect`][4] is equivalent (also see the wrapper in [golang.org/x/sys/windows][5]). If you get it working on Windows, send me a Gist and I'll gladly link to it here.

## The problems

Play around with overriding functions and you'll find that some functions can't
be overridden. A frequent problem is in-line functions. For example,
`fmt.Printf` will probably be in-lined because it's really a small wrapper
around `fmt.Fprintf`. If you disassemble a call to it you'll see something like
this:

```
TEXT main.main(SB) /home/user/dev/gofuncs/main.go
  main.go:14            0x499960                493b6610                CMPQ SP, 0x10(R14)
  main.go:14            0x499964                7636                    JBE 0x49999c
  main.go:14            0x499966                55                      PUSHQ BP
  main.go:14            0x499967                4889e5                  MOVQ SP, BP
  main.go:14            0x49996a                4883ec38                SUBQ $0x38, SP
  print.go:233          0x49996e                488b1d0b5b0d00          MOVQ os.Stdout(SB), BX
  main.go:15            0x499975                90                      NOPL
  print.go:233          0x499976                488d05ebbc0400          LEAQ go:itab.*os.File,io.Writer(SB), AX
  print.go:233          0x49997d                488d0d154a0200          LEAQ 0x24a15(IP), CX
  print.go:233          0x499984                bf0c000000              MOVL $0xc, DI
  print.go:233          0x499989                31f6                    XORL SI, SI
  print.go:233          0x49998b                4531c0                  XORL R8, R8
  print.go:233          0x49998e                4d89c1                  MOVQ R8, R9
  print.go:233          0x499991                e84a99ffff              CALL fmt.Fprintf(SB)
  main.go:28            0x499996                4883c438                ADDQ $0x38, SP
  main.go:28            0x49999a                5d                      POPQ BP
  main.go:28            0x49999b                c3                      RET
  main.go:14            0x49999c                0f1f4000                NOPL 0(AX)
  main.go:14            0x4999a0                e8bb89fdff              CALL runtime.morestack_noctxt.abi0(SB)
```

The instructions from `print.go` are the result of in-lining. The function
definition of `fmt.Printf` exists if you get a pointer to it, but if won't
matter if you insert a `JMP` there because, unless you call it through a
function pointer, nothing uses it.

Generic functions are similar have a similar problem. I'll skip the details for
brevity, but the gist is that the function you get a pointer to is different
from the function that's typically called.

Things can get weird if you try overriding methods. Take a contrived example:

```Go
type counter struct {
	A int64
}

//go:noinline
func (c *counter) Inc() {
	c.A++
}


func main() {
	c := &counter{}
	c.Inc()
	c.Inc()
	c.Inc()
	fmt.Println(c.A)
}
```

Unsurprisingly, this outputs `3`. Let's say we want to replace `Inc` with the version from this struct instead:

```Go
type doubleCounter struct {
	someOtherField int32
	A int32
}

func (dc *doubleCounter) Inc() {
	dc.A += 2
}
```

And we call it with:

```Go
func main() {
	c := &counter{}
	c.Inc()
	c.Inc()
	c.Inc()

	redefineFunc((*counter).Inc, (*doubleCounter).Inc)
	c.Inc()

	fmt.Println(c.A)
}
```

We could reasonably expect the output to be `5`, but it instead prints
`8589934595`. `doubleCounter.Inc` is compiled expecting to operate on a
`doubleCounter` struct but we've forced it to use the `counter` struct, so it
dutifully operates on the first 32-bits of `counter.A` and we get the
equivalent of `2<<32 + 3`. This is admittedly a contrived example, but you can
imagine the resulting crash if these were pointers or the chaos created if
these weren't simple integers but larger structs. And consider what would
happen if `doubleCounter` were instead:

```Go
type doubleCounter struct {
	someOtherField int32
	A int64
}
```

Now it's adding two to some portion of memory immediately our instance of
`counter`. Maybe it harmlessly updates some padding, but more likely it's
something internal to Go that will lead to a crash sooner or later. You can
expect some awful bugs if you try to replace methods this way. The only
potentially safe way to override a method is if the two structs are identical
(or, at least, the same size and you're very careful).

So, can you redefine Go functions? In general, yes. There are a few scenarios
that don't work at all, and a few that require a lot of care. But you bypass
all the safeties in the language and can pretty easily create some really nasty
bugs.

If you really must do this, I made a [package][6] to wrap this insidious code
in a friendly interface. As of right now, it only works for amd64 and I won't
recommend using it. But it's a lot of fun to hack on and PR's are welcome.

[1]: https://gist.github.com/pboyd/8b211023ade6db2010202139d80a139c
[2]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_amd64-go
[3]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_arm64-go
[4]: https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualprotect
[5]: https://pkg.go.dev/golang.org/x/sys@v0.41.0/windows#VirtualProtect
[6]: https://github.com/pboyd/redefine
