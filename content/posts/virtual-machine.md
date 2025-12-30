---
title: "Let's build a virtual machine"
date: 2022-03-18T11:00:00Z
draft: false
type: post
discussions:
- url: https://www.reddit.com/r/programming/comments/tgzh3u/lets_build_a_virtual_machine/
  site: /r/programming
related:
- /posts/useless-program
---
I once heard about a High School student who thought Europe was the capital of France. Of course that's ridiculous, but how long, do you suppose, someone can go believing Europe is in France and not the other way around? If you're far from Europe physically and mentally, I'd bet you could go a lifetime, and it wouldn't even matter. It's only a problem when someone tries to use that fact. Perhaps with an unusually hard conversation with a travel agent ("They have how many airports in Europe!?").

Unfortunately, this is like my own situation. I am, after all, a self-taught programmer who works in high-level languages. So I've held some pretty absurd ideas about how computers really work, which can linger unchallenged for a while. I think I've sorted most of these out by now, but a CompSci degree probably would have sorted them out earlier. I take a little comfort in believing I'm not alone. For instance, I've heard of programmers who think pointers always take one byte of memory or believe their favorite programming language doesn't have a stack. Those facts are just as wrong as "Europe, France", but they can persist since it's often irrelevant to many professional programmers who live a few rungs up the abstraction ladder.

I think there's a simple cure for these false facts: just try and use them. There's no cure for bad geography like a road trip. To that end, I'm going to build a virtual machine. If you're at all interested, I'd encourage you to follow along on your own.

I'm writing everything in C for this post, but there's nothing very important about the language choice. The concepts are what matter, and they will be the same in any language. One word of warning, I'm figuring some of this out as I go, if you find an error let me know so I can fix it.

My end result is on GitHub: [pboyd/robovac](https://github.com/pboyd/robovac). I'm skipping over some dull bits, but I'll link to them where relevant.

## Virtual Machines
A virtual machine, in case you didn't know, is a computer simulation of a computer. It's not as ridiculous as it sounds, but ours is for education and it will definitely be ridiculous.

To get started, this represents our computer:

```c
typedef struct Machine {
    uint8_t* memory;
    uint32_t reg[16];
} Machine;
```

Just a pointer to a memory buffer and an array of 32-bit register values. That's enough for now.

Before we can run anything we'll need to load a program and initialize the `Machine`:

```c
#define MEMORY_SIZE 4096

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <program>\n", argv[0]);
        return 1;
    }

    Machine machine = {0};
    machine.memory = malloc(MEMORY_SIZE);
    if (machine.memory == NULL) {
        return 1;
    }

    size_t code_size = load_code(machine.memory, MEMORY_SIZE, argv[1]);
    if (!code_size) {
        free(machine.memory);
        return 1;
    }

    // ...
}
```

The [`load_code`](https://github.com/pboyd/robovac/blob/9ed4333d46da0051f3b911f55cdad6154abc9015/robovac.c#L49) function reads the whole program into memory.

The program doesn't matter at this point, a single null byte in a file will do fine: `echo -ne '\0' > examples/null`.

## Instructions

You may have heard that a CPU is the brain of the computer. That is an insult to brains everywhere. CPUs must be told in such inane detail what to do that it's a wonder it's even useful, and should absolutely not be confused with any sort of intelligence on the level of, say, an average earthworm. Our simulated CPU will look at the memory at the address of its instruction pointer and blindly do what it says. Modern CPUs are more complicated than our simulation, but the idea is the same: look at an instruction in memory and do what it says.

We only have 16 registers, but one of these very precious resources will be given wholly to the instruction pointer (`IP`). It doesn't matter which register, but I'd like to save the lower numbers for general-purpose registers, so I will assign the very last register:

```c
#define REG_IP 15
```

The VM will always execute the instruction at `machine.memory+machine.reg[REG_IP]`.

An instruction consists of an opcode and zero or more operands. The whole set of instructions forms an instruction set. We could implement an existing instruction set (`x86` or ARM, for example), but rather than get bogged down with details and limits of real-world hardware, we'll design our own instruction set as we go. It's worth nothing that opcodes don't have to be a fixed size, but to keep our VM simple, our opcodes will be a single byte.

Our first instruction will be the `HLT` instruction. Which is hard-coded to cause the VM to exit. As a temporary expedient, `IP` will be incremented by 1 in the main loop.

```c
uint8_t opcode;
while (1) {
    opcode = *(machine.memory+machine.reg[REG_IP]);
    // Special case for HLT
    if (opcode == 0) {
        break;
    }
    // FIXME
    machine.reg[REG_IP]++;
}
```

So we scan the memory until there is a zero and exit.

We'll have to write a handler for every instruction. There are several ways we can do this, but I'm going with a big table of code refs. For that, we'll need some definitions:

```c
typedef void (*OpHandler)(Machine* machine, uint8_t* operands);
extern OpHandler op_handlers[];
```

And then the table of all opcode handlers:

```c
void ret(Machine* machine) {
    // FIXME: No-op for now.
    machine->reg[REG_IP]++;
}

void invalid(Machine* machine) {
    // FIXME
    fprintf(stderr, "invalid opcode\n");
    machine->reg[REG_IP]++;
}

OpHandler op_handlers[] = {
    &hlt,           // 0x00: HLT
    &invalid,       // 0x01
    &invalid,       // 0x02
    &invalid,       // 0x03
    // ...
    &invalid,       // 0xfe
    &invalid,       // 0xff
};
```

Our opcode handlers are responsible for performing any action that's needed and setting `IP` for the next instruction.

All that's left is to call our opcode handlers in the main loop:

```c
uint8_t opcode;
while (1) {
    opcode = *(machine.memory+machine.reg[REG_IP]);
    // Special case for HLT
    if (opcode == 0) {
        break;
    }

    (*op_handlers[opcode])(&machine);
}

dump_registers(machine.reg);
```

I'm also adding a [function](https://github.com/pboyd/robovac/blob/b9927d0d0f798991b6c7318efdc1822c7cbbd05c/robovac.c#L73) to print the register values at the end, so we can see the result.

[Source code at this point](https://github.com/pboyd/robovac/tree/b9927d0d0f798991b6c7318efdc1822c7cbbd05c)

## MOV

We've managed to make a complicated program that exits, unless it segfaults, which is likely. Let's try to make it do something interesting.

If you've done any assembly programming at all, you've seen `MOV`. But, if not, it copies values. Assembly always gave me the impression that `MOV` was one command with several different argument types, but it's actually a family of similar instructions that all copy values between different types of destinations and sources. We'll start by implementing `MOV r32, i32`, or copy an immediate 32-bit value into a 32-bit register (not that we have registers of any other size).

In assembly this would be something like: `MOV r0, 0x12345678`, but we don't have an assembler. So launch your favorite hex editor (if you're on Linux, I like [ghex](https://gitlab.gnome.org/GNOME/ghex)) and write your program in machine code:

```
01 00 01 23 45 67 00
```

I know, a punch card would be an improvement. Here's what's going on:

- `01` is the opcode for our new `MOV` instruction.
- `00` is the first register. We only look at the low 4 bits (the second `0`), but we must specify all 8.
- `01 23 45 67` is the 32-bit number to copy. The value is in the code so we say it's an "immediate" value.
- `00` is the opcode for our `HLT` instruction, which causes our program to terminate.

The implementation is simple enough. Add a new function to the `op_handlers` table:

```c
 OpHandler op_handlers[] = {
     &ret,           // 0x00: HLT
-    &invalid,       // 0x01
+    &mov_r32_i32,   // 0x01: MOV r32, i32
     &invalid,       // 0x02
     // ...
```

And the handler itself:

```c
// Copy a 32-bit immediate value to a register.
void mov_r32_i32(Machine* machine) {
    uint8_t* start = machine->memory + machine->reg[REG_IP];
    size_t dest = start[1] & 0xf;

    uint32_t value;
    load_uint32t(start+2, &value);

    machine->reg[dest] = value;
    machine->reg[REG_IP] += 6;
}
```

Nothing too exciting here. It loads the destination register number and value from memory, updates the register array, then moves `IP` to the start of the following instruction.

`load_uint32t` is a macro to fetch a 4-byte big endian number from memory:

```c
#define load_uint32t(src, dest) \
    *(dest) = \
    (uint32_t)((src)[0]) << 24 | \
    (uint32_t)((src)[1]) << 16 | \
    (uint32_t)((src)[2]) << 8 | \
    (uint32_t)((src)[3])
```

Most computers today use a little endian byte order (e.g. `0x01234567` is stored as `67 45 23 01`). I'm told that reversing the order requires one less hardware gate in the processor, I'll leave that explanation to someone who actually understands the hardware. But since our computer is merely virtual, and I'm trying to preserve at least a little sanity while manually entering machine code, I'm using big endian (e.g. `0x01234567` is `01 23 45 67`).

Run the VM with the program and you should see:

```
r0=0x01234567 r1=0x00 r2=0x00 r3=0x00 r4=0x00 r5=0x00 r6=0x00 r7=0x00 r8=0x00 r9=0x00 r10=0x00 r11=0x00 r12=0x00 r13=0x00 r14=0x00 IP=0x06
```
`r0` has our value, `IP` has moved forward.

[Source code at this point](https://github.com/pboyd/robovac/tree/2527c97fc14152dac5490e9bca4354e6232826e0)

## More instructions
We need a few more instructions before we can do much:

```c
void add_r32_r32(Machine* machine) {
    uint8_t* start = machine->memory + machine->reg[REG_IP];
    size_t reg1 = start[1] >> 4;
    size_t reg2 = start[1] & 0xf;

    machine->reg[reg1] += machine->reg[reg2];

    machine->reg[REG_IP] += 2;
}

void jmp_abs_i16(Machine* machine) {
    load_uint16t(machine->memory + machine->reg[REG_IP]+1, &machine->reg[REG_IP]);
}

void jmp_rel_i8(Machine* machine) {
    machine->reg[REG_IP] += (int8_t)(*(machine->memory + machine->reg[REG_IP] + 1));
}
```

Register these in the `op_handlers` table:

```c
OpHandler op_handlers[] = {
    // ...
    &add_r32_r32,   // 0x02: ADD r32, r32
    &jmp_abs_i16,   // 0x03: JMP i16
    &jmp_rel_i8,    // 0x04: JMP i8
    // ...
```

`ADD` adds values from two registers, storing the result in the first register. Since there are 16 registers we only need 4 bits for each one, and we can pack both operands in a single byte. For example, the bytecode `02 01` would increment `r0` by the value in `r1`.

`JMP` sets the next instruction that will run. We have two variants, a `JMP` that uses a fixed 16-bit address and a relative version that goes forward or backward a small number of bytes. `JMP` can be used to implement basic loops. For instance, `03 00 00` will jump back to the start of the program, and `04 00` will hang the VM in an infinite loop.

If `JMP` sounds like `goto`, then you have the right idea. In fact, it has all problems of `goto` and then some. Not only can you jump into the middle of another procedure, but you can jump to the middle of another instruction, or the middle of something that isn't code at all. Use caution.

Here is a program using these instructions:

```
01 01 00 00 00 01 02 01 02 01 03 00 0F 02 01 00
```

If we had a disassembler, the output would look like this:

```
00: 01 01 00 00 00 01      MOV r1, 1
06: 02 01                  ADD r0, r1
08: 02 01                  ADD r0, r1
0A: 03 00 0F               JMP 0xf
0D: 02 01                  ADD r0, r1
0F: 00                     HLT
```

The program sets `r1` to 1, then adds `r1` to `r2` twice, then jumps over a third `ADD` instruction before terminating.

Here's the final state:

```
r0=0x02 r1=0x01 r2=0x00 r3=0x00 r4=0x00 r5=0x00 r6=0x00 r7=0x00 r8=0x00 r9=0x00 r10=0x00 r11=0x00 r12=0x00 r13=0x00 r14=0x00 IP=0x0f
```

Note that `r0` is 2, not 3, because the third `ADD` was skipped.

[Source code at this point](https://github.com/pboyd/robovac/tree/991421b1297de6dcd1b0e3e4139af0bf8b088544)

## Conditionals
Our programs our severely limited by the lack of conditional logic, so let's fix that. First, we need a flags register, which I'm assigning to register 14:

```c
#define REG_FL 14
```

The bits in the flags register are set or cleared as side-effects of instructions. We'll start with four flags:

```c
#define FLAG_ZF     1       // Zero flag
#define FLAG_OF     1<<1    // Overflow flag
#define FLAG_CF     1<<2    // Carry flag
#define FLAG_SF     1<<3    // Sign flag
```

Our `ADD` instruction is the only one that affects any flags right now. Here's the new implementation:

```c
void add_r32_r32(Machine* machine) {
    uint8_t* start = machine->memory + machine->reg[REG_IP];
    size_t reg1 = start[1] >> 4;
    size_t reg2 = start[1] & 0xf;

    uint32_t old_value = machine->reg[reg1];
    machine->reg[reg1] += machine->reg[reg2];

    machine->reg[REG_FL] &= ~(FLAG_ZF|FLAG_OF|FLAG_CF|FLAG_SF);

    if (machine->reg[reg1] == 0)
        machine->reg[REG_FL] |= FLAG_ZF;

    if (SIGN(machine->reg[reg1]))
        machine->reg[REG_FL] |= FLAG_SF;

    if (old_value > machine->reg[reg1])
        machine->reg[REG_FL] |= FLAG_CF;

    if (SIGN(old_value) == SIGN(machine->reg[reg2]) && SIGN(machine->reg[reg1]) != SIGN(machine->reg[reg2]))
        machine->reg[REG_FL] |= FLAG_OF;

    machine->reg[REG_IP] += 2;
}
```

The zero flag (`ZF`) is set when the result of the operation is 0 and cleared for any other result.

The sign flag (`SF`) is set when the result is negative. The `SIGN` macro returns the value of highest bit in a 32-bit number: `#define SIGN(value) ((uint32_t)value >> 31)`

The carry flag (`CF`) and overflow flag (`OF`) take a bit of explaining, for which I'll recommend [this article](http://teaching.idallen.com/dat2343/11w/notes/040_overflow.txt). The gist is that `CF` is set when the result is invalid for **unsigned** numbers and `OF` is set when the result is invalid for **signed** numbers. For example, overflow is set when the result of adding two positive numbers is negative, and carry is set when two unsigned numbers are added but the result decreases.

Now that we have flags, we can create conditional jumps. These instructions work like `JMP` but only if some condition is met. For example, `JZ` ("jump if zero") jumps if the zero flag is set, it's complemented by `JNZ` ("jump if not zero"). Let's implement those:

```c
void jz_rel_i8(Machine* machine) {
    if (machine->reg[REG_FL]&FLAG_ZF)
        machine->reg[REG_IP] += (int8_t)(*(machine->memory + machine->reg[REG_IP] + 1));
    else
        machine->reg[REG_IP] += 2;
}

void jnz_rel_i8(Machine* machine) {
    if (!(machine->reg[REG_FL]&FLAG_ZF))
        machine->reg[REG_IP] += (int8_t)(*(machine->memory + machine->reg[REG_IP] + 1));
    else
        machine->reg[REG_IP] += 2;
}

// ...

OpHandler op_handlers[] = {
    // ...
    &jz_rel_i8,     // 0x05: JZ i8
    &jnz_rel_i8,    // 0x06: JNZ i8
    // ...
```

We're just doing small relative jumps for now, but that's enough for a basic loop:

```
01 00 00 00 00 0A 01 01 FF FF FF FF 02 01 06 FE 00
```

The disassembly would be:

```
00: 01 00 00 00 00 0A    MOV r0, 0xa
06: 01 01 FF FF FF FF    MOV r1, 0xffffffff   ; -1
0C: 02 01                ADD r0, r1
0E: 06 FE                JNZ 0xfe             ; -2
10: 00                   HLT
```

`r0` is our counter which starts at 10. `r1` is our step value. We don't have a `SUB` instruction right now, but we can add by -1, which is `0xffffffff`. `ADD` sets the zero flag when the result is zero, so `JNZ` jumps back two bytes unless `r0` is zero. Once `r0` does hit zero, it falls through to the `HLT` instruction to exit. This is roughly equivalent to `for (i = 10; i != 0; i--) {}`.

[Source code at this point](https://github.com/pboyd/robovac/tree/317c3e73089b8a84325f2c9fb5e570b258914694)

## Fibonacci
I will leave you with one last program. This calculates the largest [Fibonacci number](https://en.wikipedia.org/wiki/Fibonacci_number) that will fit in an unsigned 32-bit integer:

```c
01 02 00 00 00 01 09 01 02 12 07 07 09 20 03 00 06 00
```

This required one new instruction:  `MOV r32, r32`, opcode `0x9`, which copies a value from one register to another. The [implemention](https://github.com/pboyd/robovac/blob/9ed4333d46da0051f3b911f55cdad6154abc9015/ops.c#L23) is nothing new.

The disassembly:

```
00: 01 02 00 00 00 01    MOV r2, 1
06: 09 01                MOV r0, r1
08: 02 12                ADD r1, r2
0A: 07 07                JC 0x7
0C: 09 20                MOV r2, r0
0E: 03 00 06             JMP 0x6
11: 00                   HLT
```

The code loops through adding numbers until it hits an `ADD` that sets the carry flag (i.e. it overflowed a `uint32`), then it jumps out of the loop to the `HLT` instruction at the end.

The final answer ends up in `r0`:

```
r0=0xb11924e1 r1=0x1e8d0a40 r2=0x6d73e55f r3=0x00 r4=0x00 r5=0x00 r6=0x00 r7=0x00 r8=0x00 r9=0x00 r10=0x00 r11=0x00 r12=0x00 r13=0x00 r14=0x04 IP=0x11
```

`0xb11924e1` is 2,971,215,073 decimal which appears to be correct.

## Next steps
That's it for now. I was hoping to get to the stack, the heap, and interrupts, but this is too long for a blog post already. If anyone wants another post with more, and increasingly heinous, machine code examples, let me know and I'll keep going. Otherwise, [the code is on github](https://github.com/pboyd/robovac/tree/10ed4333d46da0051f3b911f55cdad6154abc9015), happy hacking.

---

- _A special thanks to Reddit user [ShinyHappyREM](https://www.reddit.com/user/ShinyHappyREM/) for [pointing out](https://www.reddit.com/r/programming/comments/tgzh3u/comment/i15pyeq/) that I mixed up little and big endian in an earlier version of this post._
- _This post initially used `RET` instead of `HLT` to exit. My thought was that programs would have one more `RET` than `CALL` which would make it exit. [Patrick Ahlbrecht](https://raccoon.onyxbits.de/blog/) suggested in an email that I should just call it `HLT` and leave `RET` for a `CALL` implementation. On reflection, I agree: my `RET` instruction bucked convention, for no real gain._

