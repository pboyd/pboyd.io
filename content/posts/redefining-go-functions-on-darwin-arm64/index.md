---
date: 2026-03-21T06:51:31-04:00
draft: false
title: Redefining Go Functions on Mac OS
type: post
---
I recently wrote about [redefining Go functions][1] which was mostly about Linux on amd64. But I ported it arm64, tested it on Linux, and figured it would work on Darwin/arm64 too. I didn't have a way to test it, so I said:

> I _think_ it will work for Darwin on Apple silicon

That may be the most naïve thing I've ever written. But honestly, I thought it would work. Darwin has `mprotect`, and the instruction encoding is the same, and I knew it worked on Intel-based Macs, so why shouldn't it work?

I eventually had a chance to test it with Github actions while porting the [package][2] that post was based on to arm64. I fixed a couple of build problems, and thought that would be it. Unfortunately, all my `mprotect` calls kept returning `EACCES` and there didn't appear to be a simple solution. It's difficult to work through a problem that can only be reproduced in CI, so I was stuck. I added a couple notes to say that I couldn't make Darwin/arm64 work and figured that would be that. It bothered me though. It bothered me a lot. But what was I going to do? Buy a used M1 Mac Mini, a [book][3] on ARM assembly, then spend all my spare time for a few weeks to port a dumb joke program about an Alan Jackson song to a platform I don't use, or even want to use? Well, yeah, apparently:

```Go
package main

import (
        "fmt"
        "os"
        "time"
)

func myTimeNow() time.Time {
        return time.Date(2026, 1, 30, 17, 0, 0, 0, time.FixedZone("Somewhere", 0))
}

func main() {
        err := redefineFunc(time.Now, myTimeNow)
        if err != nil {
                fmt.Fprintf(os.Stderr, "redefineFunc failed: %v\n", err)
                os.Exit(1)
        }

        fmt.Println(time.Now().Format(time.Kitchen))
}
```

```
$ uname -ms ; go run .
Darwin arm64
5:00PM
```

What follows is the way I found to monkey patch Go functions on a Mac. I don't recommend anyone use the Linux or Windows versions for anything real, and this one is worse. So much worse.

The code for this program is [on Github][4]. It's a bit lengthy, so I'm only pasting the highlights in this post.

## How Apple broke `mprotect`

The problem is that Darwin on arm64 doesn't allow a program to modify its code. It's locked tight. `mprotect`, and its Darwin cousin `mach_vm_protect`, block all attempts. `mmap`, `mach_vm_allocate` and `mach_vm_remap` prevent overwriting the text segment. There might be some way I didn't try, but I eventually gave up on the idea of modifying the text segment itself (of course, if you have a way, I'd love to hear about it).

Apple left one door open for self-modifying code, and then only a crack. `mmap` takes a `MAP_JIT` flag with an accompanying per-thread setting to switch all `MAP_JIT` mappings in the program from read-execute to read-write. I assume from the name this was meant to facilitate just-in-time compilation for interpreted languages and those with machine independent bytecode, like Java. Of course, `MAP_JIT` is not directly useful because a Go program's text segment isn't allocated with it. The OS allocates it read-execute without no special flags and still won't allow remapping it.

The only way forward I was able to find is to copy the program's text segment to a new mapping with `MAP_JIT`, and then execute from that copy.

## Duplicating the code

The first hurdle is just finding the address of the text segment. C simply provides an `extern`, but Go (for reasons I can't fathom) doesn't give this information up easily. But we can get a copy of Go's internal view of this information by using `runtime.lastmoduedatap` via `linkname`:

```go
//go:linkname lastmoduledatap runtime.lastmoduledatap
var lastmoduledatap *moduledata

type moduledata struct {
        // [snip]

        text, etext           uintptr
        noptrdata, enoptrdata uintptr
        data, edata           uintptr
        bss, ebss             uintptr
        noptrbss, enoptrbss   uintptr
        covctrs, ecovctrs     uintptr
        end, gcdata, gcbss    uintptr
        types, etypes         uintptr
        rodata                uintptr
        gofunc                uintptr // go.func.*
        epclntab              uintptr

        // [snip]
}
```
[source][5]

`linkname` requests the linker to bind that variable and name together, so we get pointer to Go's internal `moduledata` struct. There's no published definition of that struct, so we have to copy the definition from Go's source code. The version above is from Go 1.26, which differed a little from what was in Go 1.25. This is, of course, very brittle and Go could break it tomorrow, but it's good enough for today.

The text segment runs from the address in `text` to `etext` ("end text" presumably), but we actually need to copy from `text` to `rodata` because, as I discovered the hard way, there are cgo stubs placed between `etext` and `rodata`.

Now we can allocate a new text segment, and copy all the machine code from the original segment to our new one:

```Go
func duplicateText() (uintptr, error) {
	text := lastmoduledatap.text & pageMask
	etext := (lastmoduledatap.rodata + pageSize - 1) & pageMask

	destPtr, err := unix.MmapPtr(
		-1, 0,
		unsafe.Pointer(lastmoduledatap.end),
		etext-text,
		unix.PROT_READ|unix.PROT_WRITE|unix.PROT_EXEC,
		unix.MAP_ANON|unix.MAP_PRIVATE|unix.MAP_JIT,
	)
	if err != nil {
		return 0, fmt.Errorf("mmap JIT text (%d bytes): %w", etext-text, err)
	}

	cgo.JITWriteStart()
	defer cgo.JITWriteEnd()

	src := unsafe.Slice((*byte)(unsafe.Pointer(text)), etext-text)
	dest := unsafe.Slice((*byte)(destPtr), etext-text)
	copy(dest, src)

    cgo.ClearCache(dest)

    return uintptr(destPtr) - text, nil
}
```

The `mmap` call gets read-write-execute permissions because there's no point bothering with anything less. Apple has its own mechanism with `pthread_jit_write_protect_np` and layering the standard Unix memory protections on top is unnecessary. The [`JITWriteStart` and `JITWriteEnd`][6] calls are just cgo wrappers around `pthread_jit_write_protect_np`.

The returned value from this function is the `offset` to add to an address in the old text segment to get the equivalent address in the new text segment.

With a little pointer tomfoolery we can use the offset to call simple functions that we've copied:

```Go
func main() {
    offset, err := duplicateText()
    if err != nil {
            return err
    }

    dupTestFunc := offsetFunc(testFunc, offset)
    fmt.Println(dupTestFunc(2))
    // Prints 4
}

func testFunc(x int) int {
        return x * 2
}

var refs []any

// offsetFunc takes the address of fn and adds offset to it, then derefs that
// address as a function of the same type.
func offsetFunc[T any](fn T, offset uintptr) T {
	fnv := reflect.ValueOf(fn)
	if fnv.Kind() != reflect.Func {
		panic("not a function")
	}

	ptr := new(uintptr)
	*ptr = fnv.Pointer() + offset
	refs = append(refs, ptr)

	return *(*T)(unsafe.Pointer(&ptr))
}
```

Unfortunately, this only works for extremely simple functions right now. This variation will probably crash:

```
var multiplier int = 2

func testFunc(x int) int {
        return x * multiplier
}
```

The problem is that `multiplier` is stored in static data. `testFunc` disassembles to:

```
ADRP 1003520(PC), R27                // adrp x27, .+0xf5000
MOVD 1584(R27), R1                   // ldr x1, [x27,#1584]
MUL R1, R0, R0                       // mul x0, x0, x1
RET                                  // ret
```

That `ADRP` instruction loads the address of the memory page containing `multiplier`. But `ADRP` is relative to the address of the instruction (stored in the program counter, or PC, register). Now that we've moved the code, `pc+0xf5000` is probably pointing at unallocated space and therefore the program crashes. Or it's pointing at allocated memory and (unless you're extremely fortunate) doesn't hold the value `2` and you get the wrong answer.

To solve that problem, we need to walk through the copied text segment and update the arguments to the `ADRP` instructions to point to the same data relative to the new address. Fortunately, [`golang.org/x/arch/arm64/arm64asm`][7] makes parsing the machine code drop-dead simple. It doesn't encode new instructions though, so we'll have to handle that manually.

```Go
const adrAddressMask = uint32(3<<29 | 0x7ffff<<5)

func fixADRP(code []byte, offset uintptr) {
    destBase := uintptr(unsafe.Pointer(unsafe.SliceData(code)))
	srcBase := destBase - offset

	for i := uintptr(0); i < uintptr(len(code)); i += 4 {
		raw := code[i : i+4]
		inst, _ := arm64asm.Decode(raw)

		destPC := destBase + i
		srcPC := srcBase + i

		switch inst.Op {
		case arm64asm.ADRP:
			oldArg := int64(inst.Args[1].(arm64asm.PCRel))
			newArg := uint32((int64(srcPC&^uintptr(0xfff)) + oldArg - int64(destPC&^uintptr(0xfff))) >> 12)

			encoded := binary.LittleEndian.Uint32(raw) &^ adrAddressMask
			encoded |= (newArg & 3) << 29             // Lowest 2 bits to bits 30 and 29
			encoded |= ((newArg >> 2) & 0x7ffff) << 5 // Highest 19 bits to bits 23 to 5
			binary.LittleEndian.PutUint32(raw, encoded)

		}
	}
}
```
[source][8]

With that in place, our duplicated functions can use static data.

The last major problem with our duplicated text segment only happens when there's a `panic`. If our test function were instead:

```
var divisor int = 0

func testFunc(x int) int {
        return x / divisor
}
```

Of course this crashes, but instead of a familiar `divide by 0` it's `unknown pc`. Just because the processor can execute instructions in our new text segment, doesn't mean the Go runtime knows about it. For that, we need to register a new "module":

```Go
var newModdata moduledata

func duplicateText() (uintptr, error) {
	// ... same as before ...

    fixADRP(dest, offset)

    cgo.ClearCache(dest)

    newModdata = *lastmoduledatap
    newModdata.text += offset
    newModdata.etext += offset
    newModdata.minpc += offset
    newModdata.maxpc += offset

    newPcHeader := *lastmoduledatap.pcHeader
    newPcHeader.textStart += offset
    newModdata.pcHeader = &newPcHeader

    newModdata.textsectmap = make([]textsect, len(lastmoduledatap.textsectmap))
    for i := range lastmoduledatap.textsectmap {
            newModdata.textsectmap[i] = lastmoduledatap.textsectmap[i]
            newModdata.textsectmap[i].baseaddr += offset
    }

    lastmoduledatap.next = &newModdata

    return uintptr(destPtr) - text, nil
}
```

Our module shares the same data segments as the original one, so we just copy that one and update the text addresses. The module data is stored in a singly linked list, so we insert our copy as `next` on `lastmoduledatap`. It's important that our moduledata is statically allocated and not on the heap because we don't want the GC to collect it. Once that's in place we get a much more normal stack trace:

```
panic: runtime error: integer divide by zero

goroutine 1 [running]:
main.testFunc(0x3ab69e4ce668?)
        /Users/pboyd/dev/redefine-macos-poc/redefine.go:115 +0x38
main.fork()
        /Users/pboyd/dev/redefine-macos-poc/redefine.go:89 +0x84
main.redefineFunc[...](0x10482f130, 0x10482f120)
        /Users/pboyd/dev/redefine-macos-poc/redefine.go:21 +0x28
main.main()
        /Users/pboyd/dev/redefine-macos-poc/main.go:14 +0x34
exit status 2
```

It has the original source code lines but with addresses from the new text segment.

[The full `duplicateText` source][9]

## Switching to the duplicate

Now we have a functioning copy of the program text, but what good is that really? The program is still running from the original read-only text segment, not our read-write duplicate. This is where we need to know a bit more about Arm assembly.

First of all, we need to know about subroutine calls. On Arm, subroutines are called with the `BL` instruction. It does an unconditional branch (like `B`), and stores the return address in the link register (`lr`). The `RET` instruction jumps to whatever address in `lr`. There are two things to note about this: 1) if control the address in `lr` we control where the program executes, and 2) because the usual form of `BL` takes a PC-relative address and, because we copied the entire text segment, once we start executing in the copy we'll stay in the copy.

Secondly, we need to talk about the stack. Each (non-trivial) function gets a stack frame, which exists from the address in the frame pointer (`fp`) to the stack pointer (`sp`). Arm uses register `x29` as frame pointer. Go's function preamble stores the original `fp` value on the stack before updating the address. So the stack frame, at it most basic, looks like this:

```
-------------------content/posts/redefining-go-functions-on-darwin-arm64/index.mdcontent/posts/redefining-go-functions-on-darwin-arm64/index.md
|     prev fp     | <- fp
-------------------
|      ...        |
-------------------
|   last item     | <- sp
-------------------
```

Because the link register only holds one value it has to be saved somewhere before making a function call, so `lr` is normally pushed onto the stack immediately after the frame pointer. Go follows this convention as well. A normal stack frame then, looks like this:

```
-------------------
|     prev fp     | <- fp
-------------------
|       lr        |
-------------------
|      ...        |
-------------------
|   last item     | <- sp
-------------------
```

The practical upshot is that if we can get the frame pointer we can walk back up the stack and shift the return addresses to our copy. We need a bit of assembly code to get the `fp` value:

```assembly
TEXT ·getFrame(SB),NOSPLIT,$0-8
    MOVD R29, ret+0(FP)
    RET
```

And then a little Go code to interpret the addresses:

```Go
type frame struct {
        next *frame
        lr   uintptr
}

func getFrame() *frame
```

Then we can adjust return values all the way back up the call stack:

```Go
for f := getFrame(); f != nil; f = f.next {
        if f.lr >= origText && f.lr < origEtext {
                f.lr += offset
        }
}
```

This isn't perfect. The call stack may not include all goroutines in the program. But it works well enough if we can run it early in the main goroutine before any others are started.

The major failing of this approach is function pointers. For instance,

```Go
func main() {
        redefineFunc(time.Now, myTimeNow)

        fmt.Println(time.Now().Format(time.Kitchen))
        // Prints 5:00PM

        f := func() {
            fmt.Println(time.Now().Format(time.Kitchen))
        }
        f()
        // Prints the real time

        f() // Call it again to avoid inlining
}
```

`f` is a pointer to an anonymous function stored in `rodata` memory, so we need to search that memory for function pointers and update them. That's the job of [`patchRodataCodePtrs`][10], if you need the details.

## Patching functions

With the preliminaries out of the way, all that's left is actually patching a function. That's tricky though, because our program now runs from a `MAP_JIT` segment, and `pthread_jit_write_protect_np(0)` switches the thread from having read-execute permissions to read-write permissions. In other words, the thread that writes can't itself be executing from `MAP_JIT` memory. The simplest way I know to solve that is to switch back to the original text section when updating the code.

So we first pull the code to write the instruction into a separate function, and then access it through a function pointer so we can easily update its address.

```Go
var writeB func([]byte, int32) = _writeB

func _writeB(buf []byte, relAddr int32) {
	cgo.JITWriteStart()

	// Encode the instruction:
	// -----------------------------------
	// | 000101 | ... 26 bit address ... |
	// -----------------------------------
	inst := (5 << 26) | (uint32(relAddr>>2) & (1<<26 - 1))
	binary.LittleEndian.PutUint32(buf, inst)

	cgo.ClearCache(buf)

	cgo.JITWriteEnd()
}
```

Then, after we patch function pointers, we switch the address `writeB` so it points back to the original text segment. This uses the same `offsetFunc` function we used up above for testing:

```Go
writeB = offsetFunc(writeB, -offset)
```

---

There you have it. That's the only practical way I found to rewrite Go functions at runtime on a recent Mac. It's quite a bit more involved than I wanted it be, but haven't been able to find a simpler way.

[1]: /posts/redefining-go-functions/
[2]: https://github.com/pboyd/redefine/
[3]: https://nostarch.com/art-arm-assembly-volume-1
[4]: https://github.com/pboyd/redefine-macos-poc
[5]: https://github.com/pboyd/redefine-macos-poc/blob/main/moddata_go226.go
[6]: https://github.com/pboyd/redefine-macos-poc/blob/main/cgo/cgo.go#L24-L32
[7]: https://pkg.go.dev/golang.org/x/arch/arm64/arm64asm
[8]: https://github.com/pboyd/redefine-macos-poc/blob/main/redefine.go#L175-L211
[9]: https://github.com/pboyd/redefine-macos-poc/blob/main/redefine.go#L111-L164
[10]: https://github.com/pboyd/redefine-macos-poc/blob/main/redefine.go#L213-L264
