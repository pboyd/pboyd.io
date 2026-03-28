---
date: 2026-03-27T00:00:00-04:00
draft: false
title: "Redefining Go Functions on Mac OS: The Easy Way"
type: post
---
Two days after [my last post][1] on monkey patching Go functions for Darwin/arm64, I found a better approach. One day I hope to learn these things before spending weeks heading in the wrong direction&mdash;but not today.

The central problem is getting write access to the program's text segment (the memory containing the machine code). In the [first post][2] of this saga, I only needed to call `mprotect`. I found little information on a Darwin equivalent, so I experimented. In hindsight, I was close to the solution but missed it. Instead, I dove into Go's plumbing and piled one hacky solution on top of another until it worked. Good times, but not good code.

This version clones the text segment into a new read-write allocation, then uses `mach_vm_remap` to replace the original text segment with a read-execute mapping of the same physical memory. If our program's memory normally looks like this:

{{< autoimg
    src="mem-before.svg"
    link="mem-before.svg"
    alt="Memory layout before" >}}

We want to turn it into this:

{{< autoimg
    src="mem-after.svg"
    link="mem-after.svg"
    alt="Memory layout after" >}}

Both virtual memory allocations share the same physical memory&mdash;one for writing, one for executing.

## Duplicating the code

Like the earlier version, we start by getting the text segment's start and end addresses from Go's internal `moduledata` via `linkname`:

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

    // struct continues, just get the beginning
}
```
[source][4]

All we need from `lastmoduledatap` is the `text` and `etext` addresses, which we use to clone the text segment:

```Go
var pageSize = uintptr(syscall.Getpagesize())
var pageMask = ^(pageSize - 1)

func getWritableText() (uintptr, error) {
	// Align text and etext to page boundaries
	text := lastmoduledatap.text & pageMask
	etext := (lastmoduledatap.etext + pageSize - 1) & pageMask
	size := etext - text

	newText, err := unix.MmapPtr(-1, 0, nil, size,
		unix.PROT_READ|unix.PROT_WRITE,
		unix.MAP_ANON|unix.MAP_PRIVATE,
	)
	if err != nil {
		return 0, fmt.Errorf("mmap: %w", err)
	}

	src := unsafe.Slice((*byte)(unsafe.Pointer(text)), size)
	dest := unsafe.Slice((*byte)(newText), size)
	copy(dest, src)

    // ...
}
```

This is where I went wrong before. Apple will not permit `PROT_WRITE` and `PROT_EXEC` in the same mapping unless there's a `MAP_JIT` flag, so I added `MAP_JIT`. That worked, but I was unable to use a `MAP_JIT` mapping to replace the original text segment.

Now that we have a copy of the text segment, we need to replace the original. Apple provides the criminally under-documented `mach_vm_remap` for the purpose. Apple's [official docs][3] acknowledge its existence and list the arguments&mdash;nothing more. The best documentation I've found is an [old page on mit.edu][5], but it only documents a similar function called `vm_remap`. Perhaps if I were a real Apple dev, I'd know where to look. Instead, I've pieced together what I could find with details from the C header files for this cgo wrapper:

```Go
/*
#include <mach/mach.h>
#include <mach/mach_vm.h>
*/
import "C"

func vmRemap(addr uintptr, srcAddr uintptr, size uintptr) (unsafe.Pointer, error) {
	var vmAddr C.mach_vm_address_t
	vmAddr = C.mach_vm_address_t(addr)

	var flags int
	if addr == 0 {
		flags |= C.VM_FLAGS_ANYWHERE
	} else {
		flags |= C.VM_FLAGS_FIXED | C.VM_FLAGS_OVERWRITE
	}

	var curProt, maxProt C.vm_prot_t

	ret := C.mach_vm_remap(
		C.mach_task_self_,
		&vmAddr,
		C.mach_vm_address_t(size),
		0,
		C.int(flags),
		C.mach_task_self_,
		C.mach_vm_address_t(srcAddr),
		0, // don't copy
		&curProt,
		&maxProt,
		C.VM_INHERIT_NONE,
	)

	if ret != 0 {
		return nil, kernErr(ret)
	}

	return unsafe.Pointer(uintptr(vmAddr)), nil
}
```

We use the wrapper like this:

```Go
	err = unix.Mprotect(dest, unix.PROT_READ|unix.PROT_EXEC)
	if err != nil {
		return 0, fmt.Errorf("mprotect r-x: %w", err)
	}

	_, err = vmRemap(text, uintptr(newText), size)
	if err != nil {
		return 0, fmt.Errorf("vmRemap: %w", err)
	}
```

We call `mach_vm_remap` with a specific address and `VM_FLAGS_FIXED|VM_FLAGS_OVERWRITE` to replace the existing text mapping. The 8th argument, `copy`, is `0`, indicating we want to remap the physical pages, not copy them.

The new mapping inherits the protections from the source page, so we need `mprotect` to mark it read-execute first. Otherwise, we can't execute anything in the program, including the code to handle the `SIGBUS` signal this generates. When your `SIGBUS` handler itself generates `SIGBUS`, you've got real problems.

The final step is to revert the `mprotect` call on the copy:

```Go
	err = unix.Mprotect(dest, unix.PROT_READ|unix.PROT_WRITE)
	if err != nil {
		return 0, fmt.Errorf("mprotect rw-: %w", err)
	}
```

Now we have separate virtual address ranges for writing and executing, with the same underlying physical memory.

## Patching functions

Inserting the `B` instruction is nearly unchanged from the [Linux version][6]:

```Go
	addr := reflect.ValueOf(fn).Pointer()
	buf := unsafe.Slice((*byte)(unsafe.Pointer(addr+writeOffset)), 4)

	dest := reflect.ValueOf(newFn).Pointer() // Where to jump to
	target := int32(dest - addr)

	// Encode the instruction:
	// -----------------------------------
	// | 000101 | ... 26 bit address ... |
	// -----------------------------------
	inst := (5 << 26) | (uint32(target>>2) & (1<<26 - 1))

	binary.LittleEndian.PutUint32(buf, inst)
	cacheflush(buf)
```

The difference is that instead of writing to the address the Go runtime knows, we write to that address offset by the distance to the writable copy:

```
writeOffset = uintptr(newText) - text
```

The full source is on GitHub: [redefine-mac-poc][7]. These changes are also in [github.com/pboyd/redefine][8].

[1]: /posts/redefining-go-functions-on-mac-os/
[2]: /posts/redefining-go-functions/
[3]: https://developer.apple.com/documentation/kernel/1402218-mach_vm_remap
[4]: https://github.com/pboyd/redefine-macos-poc/blob/main/moddata.go
[5]: https://web.mit.edu/darwin/src/modules/xnu/osfmk/man/vm_remap.html
[6]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_arm64-go-L29-L40
[7]: https://github.com/pboyd/redefine-macos-poc
[8]: https://github.com/pboyd/redefine
