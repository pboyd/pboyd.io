---
date: 2026-03-27T00:00:00-04:00
draft: false
title: "Redefining Go Functions on Mac OS: The Easy Way"
type: post
---
Two days after [my last post][1] on monkey patching Go functions for Darwin/arm64, I found a better way to do it. One day, I hope to learn these things before spending weeks heading in the wrong direction. But alas, not today.

The problem is simply getting write access to the program's text segment (the memory containing the machine code). In the [first post][2] of this saga, I only needed to call `mprotect`. I couldn't find much information on an equivalent for Darwin. While I did experiment, and spent a while near the ultimate solution, I didn't find it. Instead, I dove headlong into Go's plumbing and piled one hacky solution on top of another until it worked. Good times, but not good code.

With this version, the plan is to clone the text segment into a new read-write allocation, then use `mach_vm_remap` to replace the original text segment with a read-execute mapping of the same physical memory. If our program's memory normally looks like this:

{{< autoimg
    src="mem-before.svg"
    link="mem-before.svg"
    alt="Memory layout before" >}}

We want to turn it into this:

{{< autoimg
    src="mem-after.svg"
    link="mem-after.svg"
    alt="Memory layout after" >}}

So we have separate virtual memory allocations for writing and executing, but both point to the same physical memory.

## Duplicating the code

The first step is the same as in the complicated version. We need start and end addresses of the text segment, which we can get from Go's internal `moduledata` through `linkname`:

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

This is where I went wrong before. Apple will not permit `PROT_WRITE` and `PROT_EXEC` in the same mapping unless there's a `MAP_JIT` flag, so I asked `mmap` for a read-write-execute mapping and added `MAP_JIT`. That worked. But `MAP_JIT` regions have extra limitations which prevent the remap.

Now that we have a copy of the text segment, we need to replace the original one. Apple provides `mach_vm_remap` for that, which we'll need to call through cgo. I've yet to find docs for `mach_vm_remap`. Apple's [apparently official docs][3] only list the arguments, and there's an [old page on mit.edu][5] for a similar function called `vm_remap`. The rest I've had to piece together from the C header files. Here's a Go wrapper for `mach_vm_remap`:

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

We call `mach_vm_remap` with a specific address and `VM_FLAGS_FIXED` and `VM_FLAGS_OVERWRITE` so that it will replace the existing text mapping. The 8th argument, `copy`, is `0`, indicating that we don't want to copy the contents, but remap the physical pages.

The new mapping inherits the protections from the source page, so we need `mprotect` to mark it read-execute first. Otherwise, we lose access to execute anything in the program, including the code to handle the `SIGBUS` signal this generates. When your `SIGBUS` handler itself generates `SIGBUS`, you've got real problems.

The final step is to revert the prior `mprotect` call on the copy:

```Go
	err = unix.Mprotect(dest, unix.PROT_READ|unix.PROT_WRITE)
	if err != nil {
		return 0, fmt.Errorf("mprotect rw-: %w", err)
	}
```

Now we have separate virtual address ranges for writing and executing, but the underlying physical memory is the same.

## Patching functions

Inserting the `B` instruction in the function is nearly unchanged from the [Linux version][6] of this program:

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

The only difference is that instead of writing to the address of the function as the Go runtime knows it, we write to the address offset by the distance to the writable copy:

```
writeOffset = uintptr(newText) - text
```

The full source code is on GitHub: [redefine-mac-poc][7]. And these changes are incorporated into [github.com/pboyd/redefine][8].

[1]: /posts/redefining-go-functions-on-mac-os/
[2]: /posts/redefining-go-functions/
[3]: https://developer.apple.com/documentation/kernel/1402218-mach_vm_remap
[4]: https://github.com/pboyd/redefine-macos-poc/blob/main/moddata.go
[5]: https://web.mit.edu/darwin/src/modules/xnu/osfmk/man/vm_remap.html
[6]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_arm64-go-L29-L40
[7]: https://github.com/pboyd/redefine-macos-poc
[8]: https://github.com/pboyd/redefine
