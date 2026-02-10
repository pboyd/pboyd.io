---
date: 2026-02-10
draft: false
title: Redefining Go Functions
type: post
---
I once wrote a [Perl subroutine][1] that would [memoize][7] the subroutine that
called it. That much was useful, but then it inserted a copy of itself into the
caller, so that _its_ callers would be memoized too. A well-placed call to
`aggressively_memoize` could back-propagate to the whole codebase, spreading
functional purity like a virus. The resulting program would get faster as it
used more memory and became increasingly static.

That was possible because Perl, like many interpreted languages, allows
functions to be rewritten at runtime:

```Perl
no strict 'refs';
*{$caller} = $new_sub;
```

Overuse of this feature earned it the derisive nickname "monkey patching".
Spend a couple hours debugging why your random numbers aren't so random only to
discover you have a mock RNG implanted by some distant dependency and you'll
hate it too. But these days I program mostly in Go where such nonsense isn't
possible. Right?

Well, no, not exactly. True, Go doesn't offer this as a language feature. But a
CPU executes instructions from memory, and we can modify memory. Did Go
fundamentally change all that? Not at all. In fact, Go gives us all the
low-level tools we need to do the job.

Let's say I prefer Alan Jackson's sense of time over whatever reality
`time.Now` cares to remind me of. So I want this function to replace
`time.Now`:

```Go
func myTimeNow() time.Time {
	return time.Date(2026, 1, 30, 17, 0, 0, 0, time.FixedZone("Somewhere", -5))
}
```

The first thing we need is the address of the real `time.Now`. The easiest way
is with `reflect`:

```Go
func main() {
	addr := reflect.ValueOf(time.Now).Pointer()
	fmt.Printf("0x%x\n", addr)
}
```

Run this program and you'll get an address. On my computer:

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

The actual addresses may be different for you, but the address from the program
output will match the instruction address in the disassembler output. That's
because Go function pointers point to the function's entry point.

We don't know the length of the function, but we can guess that it's at least 8
bytes and get a slice based on that:

```Go
func main() {
	addr := reflect.ValueOf(time.Now).Pointer()
	buf := unsafe.Slice((*byte)(unsafe.Pointer(addr)), 8)
	spew.Dump(buf)
}
```

Run that and you'll see:
```
$ go build -o main && ./main
([]uint8) (len=8 cap=8) {
 00000000  49 3b 66 10 0f 86 84 00                           |I;f.....|
}
```

`49 3b 66 10` matches the first instruction from the disassembled output.

Now that we can find a function and read its machine instructions, all that's
left is to modify its behavior. Copying the instructions from our replacement
function to the location of the original function seems logical, but relocating
machine instructions requires adjusting any relative addresses. That's
solvable, but the replacement function could still be bigger than the original,
and then we'd need another solution anyway.

The easiest approach is to write a `JMP` (or branch) instruction at the
beginning of the original function to redirect the processor to our new
function. Because it's a `JMP`, not a `CALL`, the `RET` from our replacement
function will return to the original caller and none of the remaining
instructions from the original function will execute. As long as the arguments
are the same for both functions, the caller will be none the wiser.

On x86, the code to encode the instruction looks like:

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

But if you run it, you'll just get a segfault:
```
unexpected fault address 0x499400
fatal error: fault
[signal SIGSEGV: segmentation violation code=0x2 addr=0x499400 pc=0x4a3c9c]
```

Letting a program modify its own code is dangerous, which is why protected
memory has been standard for decades. But getting around it is easy&mdash;we just
need to change the permissions on that memory page. On Unix systems, we do that
with `mprotect(2)`. The start address has to be page-aligned, so we need a
helper function:

```Go
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

There you go. It's 5PM. It's always 5PM.

[Here's the full source code.][2]

If you're on ARM64, you'll need [this version][3]. Aside from different
instructions, ARM also requires clearing the instruction cache. (I've only
tested the ARM64 version on a Raspberry Pi 4 running Linux. I _think_ it will
work for Darwin on Apple silicon but I don't have hardware to test it&mdash;if you
try it, let me know how it goes.)

If you're on Windows, you won't have `mprotect`. Supposedly
[`VirtualProtect`][4] is equivalent (also see the wrapper in
[golang.org/x/sys/windows][5]). If you get it working on Windows, send me a
Gist and I'll gladly link to it here.

## The problems

Play around with overriding functions and you'll find that some functions can't
be overridden. Inline functions are a frequent culprit. For example,
the compiler will probably inline `fmt.Printf` because it's a small wrapper
around `fmt.Fprintf`. If you disassemble a call to it, you'll see something like
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

The instructions from `print.go` result from inlining. The function
definition of `fmt.Printf` exists if you get a pointer to it, but inserting a
`JMP` there won't matter&mdash;nothing calls that address unless you use a
function pointer.

Generic functions have a similar problem. For brevity, I'll skip the details,
but the gist is that the function you can get a pointer to is different from
the function that's typically called.

Overriding methods introduces additional problems. A simple example:

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
	fmt.Println(c.A)
}
```

Unsurprisingly, this outputs `2`. Let's say we want to replace `Inc` with the version from this struct instead:

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

	redefineFunc((*counter).Inc, (*doubleCounter).Inc)
	c.Inc()

	fmt.Println(c.A)
}
```

If this worked perfectly, the output would be `4`. But it actually prints
`8589934594`. `doubleCounter.Inc` is compiled expecting to operate on a
`doubleCounter` struct, but we've forced it to use the `counter` struct.
`doubleCounter.A` is at the same location as the high 32-bits of `counter.A`, so
the output is `2<<32 + 2`, or `8589934594`.

This is contrived, but you can imagine the resulting crash
if these were pointers or the chaos if these weren't simple integers
but larger structs. Also consider what would happen if `doubleCounter` were
instead:

```Go
type doubleCounter struct {
	someOtherField int32
	A int64
}
```

Now it's adding two to some portion of memory immediately after our instance of
`counter`. Maybe it harmlessly updates some padding. Maybe it corrupts the heap
or overwrites an unrelated variable on the stack. Who knows exactly? But I do
know you can expect some awful bugs. The only potentially safe way to override
a method is if the two structs are identical (or, at least, the same size and
you're very careful).

So, yes, you can redefine Go functions&mdash;sometimes. Expect bugs.

If you really must do this, I made a [package][6] to wrap this insidious code
in a friendly interface. It only works on Linux/Unix and AMD64 (I hope to port
it to ARM soon). For all the reasons above (and a few I didn't cover), I can't
recommend using it. But it's fun to hack on and PRs are welcome.

[1]: https://gist.github.com/pboyd/8b211023ade6db2010202139d80a139c
[2]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_amd64-go
[3]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_arm64-go
[4]: https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualprotect
[5]: https://pkg.go.dev/golang.org/x/sys@v0.41.0/windows#VirtualProtect
[6]: https://github.com/pboyd/redefine
[7]: https://en.wikipedia.org/wiki/Memoization
