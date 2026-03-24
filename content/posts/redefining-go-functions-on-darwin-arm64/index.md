---
date: 2026-03-23T00:00:00-04:00
draft: false
title: Redefining Go Functions on Mac OS
type: post
---
I recently wrote about [redefining Go functions][1], which was mostly about Linux on amd64. But I ported it to arm64, tested it on Linux, and figured it would work on Darwin/arm64 too. Lacking a way to test it, I said:

> I _think_ it will work for Darwin on Apple silicon

That may be the most naïve thing I've ever written, but I thought it would work. The instruction encoding is the same as arm64 on any other OS, and the system calls are the same as those on Intel-based Macs. Why shouldn't it work?

While porting the [package][2] the original post was based on to arm64, I had a chance to test it and found that my `mprotect` calls always failed. I couldn't find a simple solution, and since I could only test it through GitHub actions, I gave up. I added a note saying that Darwin/arm64 doesn't work and figured that would be that. Leaving it unfinished bothered me, but what was I going to do? Buy a used Mac Mini, a [book][3] on ARM assembly, and then spend all my spare time for a few weeks porting a dumb joke program about an Alan Jackson song to a platform I don't even want to use? Well, yes, apparently that's what I was going to do.

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
$ uname -ms
Darwin arm64
$ go run .
5:00PM
```

This post explains how it works. The code for this program is [on GitHub][4]. It's lengthy, so I'm only pasting the highlights here.

## How Apple broke `mprotect`

On other platforms, we only need to call `mprotect` for read-write-execute permissions on the program's text segment (i.e. the memory segment with the executable code). The problem is that for Darwin on arm64, Apple locked it down tight. `mprotect`, `mmap`, and their Darwin cousins (`mach_vm_protect`, `mach_vm_allocate`, and `mach_vm_remap`) block every attempt to get read-write access to the text segment. I tried a lot of things, but they all failed, so I eventually abandoned modifying the text segment itself (of course, if you know of something I overlooked, please share).

Apple did leave one door open for self-modifying code: the `MAP_JIT` flag to `mmap`. When combined with the non-standard function `pthread_jit_write_protect_np`, a thread can swap between read-execute and read-write permissions to `MAP_JIT` memory. It's not much to work with, because our text segment isn't allocated with `MAP_JIT` and we can't remap it. To use it, we have to allocate a new text segment.

The plan, then, is to copy the program's text segment to a new mapping with `MAP_JIT`, and execute from that copy.

## Duplicating the code

Before we can copy the text segment, we need to find it. C provides `extern` variables for `text` and `etext`, but Go&mdash;for reasons I cannot fathom&mdash;doesn't give this information easily. But Go's runtime has this information internally, and we can get a copy of it through `linkname`:

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

`linkname` binds that variable to Go's internal `moduledata`. There's no published definition of that struct, so we have to copy the definition from Go's source code. The version above is from Go 1.26, which differed slightly from 1.25. This is brittle, and Go could break it tomorrow, but it's good enough for today.

The text segment runs from the address in `text` to `etext` ("end text"), but we need to copy from `text` to `rodata` because, as I discovered the hard way, the linker places cgo stubs between `etext` and `rodata`.

Now we can allocate a new text segment and copy all the machine code:

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

The `mmap` call gets read-write-execute permissions because Apple has its own protection mechanism with `pthread_jit_write_protect_np`; layering the standard Unix memory protections on top is unnecessary. The [`JITWriteStart` and `JITWriteEnd`][6] calls are thin cgo wrappers around `pthread_jit_write_protect_np`.

This function returns the offset to add to an address in the old text segment to get the equivalent address in the new text segment.

With a little pointer tomfoolery, we can use the offset to call simple functions that we've copied:

```Go
func main() {
    offset, _ := duplicateText()

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

Unfortunately, it only works for trivial functions. This variation probably crashes:

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

That `ADRP` instruction loads the address of the memory page containing `multiplier`. But `ADRP` is relative to the address of the instruction (stored in the program counter, or PC, register). Now that we've moved the code, `pc+0xf5000` is probably pointing at unallocated space, so the program crashes. Or it's pointing at allocated memory, which is unlikely to hold the value `2`, so you get the wrong answer.

To solve that problem, we need to walk through the copied text segment and update the arguments to the `ADRP` instructions to point to the same data relative to the new address. [`golang.org/x/arch/arm64/arm64asm`][7] makes parsing (although not encoding) the instructions easy.

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

`BL` (`CALL` in Go assembly) also takes a PC-relative address and would normally need the same adjustment. But since we copied the entire text segment, those addresses point to their equivalent function in the copy.

With that in place, our duplicated functions can use static data.

The last major problem with our duplicated text segment only happens when there's a `panic`. If our test function were instead:

```
var divisor int = 0

func testFunc(x int) int {
        return x / divisor
}
```

As you probably expect, it crashes, but instead of a familiar `divide by 0` it's `unknown pc`. The processor gladly executes instructions from our new text segment, but the Go runtime doesn't know what's at those addresses. To fix it, we need to register a new "module":

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

Our module shares the same data segments as the original one, so we copy that one and update the text addresses. The module data is stored in a singly linked list, so we insert our copy as `next` on `lastmoduledatap`. It's important that our moduledata is statically allocated and not on the heap to prevent GC collection. Once that's in place, we get a much more normal stack trace:

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

Now we have a functioning copy of the program text, but what good is that? The program is still running from the original read-only text segment, not our read-write duplicate. To solve this, we need to know two things about Arm assembly.

First, subroutine calls. On Arm, subroutines are called with the `BL` instruction. It does an unconditional branch (like `B`), and stores the return address in the link register (`lr`). The `RET` instruction jumps to the address in `lr`, so if we can update those `lr` addresses, we can switch our program to run anything.

Second, the stack. Each (non-trivial) function gets a stack frame, which exists from the address in the frame pointer (`fp`) to the stack pointer (`sp`). Arm uses register `x29` as frame pointer. Go's function preamble stores the original `fp` value on the stack before setting `fp` to its new value. So the stack frame, at its most basic, looks like this:

```
-------------------
|     prev fp     | <- fp
-------------------
|      ...        |
-------------------
|   last item     | <- sp
-------------------
```

Because the link register only holds one value, it must be saved before making function calls. The normal convention, which Go follows, is to push `lr` onto the stack immediately after the frame pointer:

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

If we get the frame pointer, we can walk back up the stack and shift the return addresses to our copy. We need a small assembly function to get the `fp` value:

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

Then we can adjust return addresses all the way back up the call stack:

```Go
for f := getFrame(); f != nil; f = f.next {
        if f.lr >= origText && f.lr < origEtext {
                f.lr += offset
        }
}
```

Unfortunately, the call stack only belongs to a single goroutine. But once we're running from the duplicate text, any new goroutines will also be in the duplicate. To be most effective, switch the main goroutine early, before starting any other goroutines.

The major failing of this approach is function pointers.

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

`f` is a pointer to an anonymous function stored in `rodata` memory, so we need to search that memory for function pointers and update them. See [`patchRodataCodePtrs`][10] for details.

## Patching functions

With the preliminaries out of the way, we can finally patch a function. Unfortunately, `pthread_jit_write_protect_np(0)` switches the thread from having read-execute permissions on `MAP_JIT` memory to read-write permissions. In other words, the thread that writes can't itself be executing from `MAP_JIT` memory. The simplest solution I've found is to switch back to the original text section when updating the code.

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

Then, after we patch function pointers, we switch the address `writeB` so it points back to the original text segment (`offsetFunc` was defined in the first section of this post).

```Go
writeB = offsetFunc(writeB, -offset)
```

---

With that, we've reached the end. That's the only way I found to monkey patch Go functions on a recent Mac. It works in all scenarios that I've thought to test, but given the number and severity of the bugs encountered, I've surely missed something. Don't use these techniques for anything serious (unless you work for [bytedance][11], perhaps). I suppose I should close by thanking Apple for making this all possible: without you, my original program would _just work_.

[1]: /posts/redefining-go-functions/
[2]: https://github.com/pboyd/redefine/
[3]: https://nostarch.com/art-arm-assembly-volume-1
[4]: https://github.com/pboyd/redefine-macos-poc
[5]: https://github.com/pboyd/redefine-macos-poc/blob/main/moddata_go226.go
[6]: https://github.com/pboyd/redefine-macos-poc/blob/main/cgo/cgo.go#L24-L32
[7]: https://pkg.go.dev/golang.org/x/arch/arm64/arm64asm
[8]: https://github.com/pboyd/redefine-macos-poc/blob/main/redefine.go#L178
[9]: https://github.com/pboyd/redefine-macos-poc/blob/main/redefine.go#L111-L164
[10]: https://github.com/pboyd/redefine-macos-poc/blob/main/redefine.go#L226
[11]: https://github.com/bytedance/sonic/tree/main/loader
