---
date: 2026-03-28T00:00:00-04:00
draft: false
title: "Redefining Go Functions on Mac OS: The Easy Way"
type: post
---
[My last post][1] showed a complicated way to monkey patch Go functions on Darwin/arm64. The problem I was trying to solve is getting write access to the program's text segment (the memory containing the machine code). In the [first post][2] of this saga, I only needed to call `mprotect`. But, on Apple silicon, `mprotect` alone is insufficient to make the text segment writable. I tried some simple approaches, but overlooked the solution below and instead dove into Go's internals, piling one hacky solution on top of another until it worked. Good times, but not good code.

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
	pcHeader     *pcHeader
	funcnametab  []byte
	cutab        []uint32
	filetab      []byte
	pctab        []byte
	pclntable    []byte
	ftab         []functab
	findfunctab  uintptr
	minpc, maxpc uintptr

	text, etext           uintptr // <- The only fields we need
	noptrdata, enoptrdata uintptr
	data, edata           uintptr
	bss, ebss             uintptr
	noptrbss, enoptrbss   uintptr
	covctrs, ecovctrs     uintptr
	end, gcdata, gcbss    uintptr
	types, etypes         uintptr
	rodata                uintptr
	gofunc                uintptr

	// The struct continues, but we only need the beginning
}
```
[source][4]

All we need from `lastmoduledatap` is the `text` and `etext` addresses:

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

Now that we have a copy of the text segment, we need to replace the original. Apple provides `mach_vm_remap` for this. Apple's [official docs][3] acknowledge its existence and list the arguments&mdash;nothing more. A real Apple dev might know where to look, but I've pieced together what documentation I could find with details from the C header files for this cgo wrapper:

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

	err = unix.Mprotect(dest, unix.PROT_READ|unix.PROT_WRITE)
	if err != nil {
		return 0, fmt.Errorf("mprotect rw-: %w", err)
	}
```

We call `mach_vm_remap` with a specific address and `VM_FLAGS_FIXED|VM_FLAGS_OVERWRITE` to replace the existing text mapping. The 8th argument, `copy`, is `0`, indicating we want to remap the physical pages, not copy them.

It's odd to call `mprotect` to get read-execute permissions only to immediately revert it, but skipping this step would be a catastrophe: the text segment wouldn't be executable, and consequently the next instruction triggers `SIGBUS`. Normally, the Go runtime panics on `SIGBUS`, but when the handler itself triggers `SIGBUS` the program is instead stuck in a busy loop. To make it even worse, the `SIGINT` and `SIGTERM` handlers are affected in the same way. `SIGKILL` is the only way out. New mappings inherit the protection setting from the source, so the first `mprotect` ensures that the text segment is always executable, and the second `mprotect` call restores write access.

Now we have separate virtual address ranges for writing and executing, with the same underlying physical memory. We know the distance between the two, so for any executable address we can find the writable equivalent.

I understand how it works, but I doubt I'll ever get used to it&mdash;it disagrees with my intuition. Consider [the tests from `redefine`][9]:

```Go
	execSlice := unsafe.Slice((*byte)(unsafe.Pointer(ptr)), 4)
	editSlice := unsafe.Slice((*byte)(unsafe.Pointer(ptr+offset)), 4)

	// The content should be the same
	assert.Equal(editSlice, execSlice)

	editSlice[0] = 0
	editSlice[1] = 1
	editSlice[2] = 2
	editSlice[3] = 3

	// The content should still be the same after changing the editable copy
	assert.Equal(editSlice, execSlice)
```

Writes to `editSlice` affect `execSlice`. Trippy.

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

The difference is that instead of writing to the address the Go runtime knows, we write to that address plus the pre-calculated `writeOffset`.

The full source is on GitHub: [redefine-mac-poc][7]. These changes are also in [github.com/pboyd/redefine][8].

All the caveats from the first post apply for this version too: patching functions this way will cause bugs. I don't know what to do with this technique. One day, perhaps, I'll stumble upon a practical use for it, but until then, I'm filing it under "weird programming tricks".

[1]: /posts/redefining-go-functions-on-darwin-arm64/
[2]: /posts/redefining-go-functions/
[3]: https://developer.apple.com/documentation/kernel/1402218-mach_vm_remap
[4]: https://github.com/pboyd/redefine-macos-poc/blob/main/moddata.go
[5]: https://web.mit.edu/darwin/src/modules/xnu/osfmk/man/vm_remap.html
[6]: https://gist.github.com/pboyd/1e1018de131e0f27a3bef1f377952c2e#file-redefine_func_arm64-go-L29-L40
[7]: https://github.com/pboyd/redefine-macos-poc
[8]: https://github.com/pboyd/redefine
[9]: https://github.com/pboyd/redefine/blob/v0.4.0/internal/static/remap_writable_darwin_arm64_test.go#L14
