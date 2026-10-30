# The L0 Programming Language — Runtime and Compilation Target

This file is part of the specification of L0, with [L0.md](L0.md), which
has sections 1 to 9 and 11, and the hosts' files under [boards/](boards/).
It is section 10 of the specification, and keeps its numbers, so a
reference to "section 10.3" anywhere means this file. It is normative, as
the rest is.

## 10. Compilation target

This section describes what an L0 compiler emits. It is part of the
specification because the L0 compiler must emit exactly this, and because the
runtime it links against is a fixed interface.

### 10.1 Value representation

**Every L0 value is an `i64`.** The type checker has already proved the program
correct, so no type information survives into the generated code.

- `int` — the value itself
- `bool` — 0 for false, 1 for true
- `float` — the float's key (6.17): its IEEE 754 binary64 bits `b`, with
  bits 0 to 62 flipped when bit 63 is set, that is `b xor ((b ashr 63) lshr
  1)`. It is not a pointer, so a block's mask has no bit for it. Each
  operation decodes its arguments to a `double`, computes with the
  instruction of that name, and encodes the result
- `(list T)` — a pointer to a cons cell, cast to `i64`. The empty list is 0.
- a data type — a pointer to a data block, cast to `i64`, except a word
  wrapper
- a **word wrapper**, a data type declared without type parameters, with
  exactly one constructor, of exactly one field, of type `int`, `bool`, or
  `float`, such as `(data Space (Space int))` — its field's word itself, as
  that type is represented. Constructing one, taking it apart with `match`,
  and reading or replacing its field are the identity on the word, and
  nothing about it is counted: a block's mask has no bit for a field of a
  word wrapper's type, and a type parameter that stands for one is of the
  kind that is not counted (10.2). `eq` and `compare` on two of its values
  are its field's, as they were, and `hash` is its field's too (6.9), with
  no tag
- `(array T)` — a pointer to an array block, cast to `i64`. An empty array is
  a block too, never 0
- `bytes` — a pointer to a bytes block, cast to `i64`. Empty bytes are a
  block too, never 0

A cons cell is two consecutive `i64` words: the element, then the rest of the
list. A data block is one `i64` tag followed by one `i64` per field. A
constructor's tag is its zero-based position in its `data` declaration. Every
block is allocated large enough for the widest constructor of its type, and
the words past a narrower constructor's fields are 0, so two values built
with one constructor have the same words wherever their fields do.

Every block also has a header word immediately before its first word, so a
value still points at the element or the tag. The header holds a reference
count, the block's size in words, and a mask with bit k set when word k is a
pointer to another block. Only the static type knows whether a list's
elements are pointers, so the compiler supplies the mask when it allocates:
a cons cell's is 2 when its elements are `int` or `bool` and 3 when they are
lists, data, arrays, or bytes, and a data block's has bit i + 1 set for each
field i of list, data, array, or bytes type. A field whose declared type
mentions a parameter has the type the construction gives it (section 5.6),
so the same constructor may have different masks: `(Some 5)`'s field is not
a pointer and `(Some "a")`'s is. The mask has 32 bits and word 0 is the tag,
which is why a constructor has at most 31 fields.

An array does not fit that header, whose size field has 8 bits, so its
header has size 0, which no other block has, since a cons cell is 2 words
and a data block at least 1. An array block's word 0 is its length and
element i is word i + 1, and its mask is 1 when the elements are lists,
data, arrays, or bytes and 0 otherwise.

A bytes block has an array's header with mask 2, and word 0 is its length,
as for an array, but byte i is the byte at offset i from the start of word
1, one per byte. Bit 0 is clear, so everything that frees an array frees
bytes too, as an array whose elements are not pointers, and bit 1, which no
array has, is what tells bytes from an `(array int)` to `eq`, `hash`, and
`compare`, which see only the block (section 10.3).

Because every value is one word, every function has the same shape of
signature and every local variable is one `i64` slot.

### 10.2 Generated symbols

An L0 function named `f` in the program compiles to `fastcc i64
@l0_f_f(i64, ...)`, and one named `f` in the prelude to `@l0_p_f`. The two
prefixes are what allow a prelude and a program to each define `f`, per
section 7.1. Every L0 function, and every call of one, uses LLVM's fast
calling convention, `fastcc`, which no code outside the program calls, so
that each target may pass the words in as many registers as it has (10.3);
only `@l0_f_main`, below, which the runtime calls, has the C convention.

**A function with type parameters** compiles to one function per
combination of whether each type parameter stands for a *counted* type —
a list, data, array, or `bytes` type, whose values section 10.3 counts — or
for `int` or `bool`. A copy is named for the function with a `.` and one
digit per type parameter, in order, `1` for counted and `0` for not:
`rev_onto` of section 4.1 compiles to `@l0_f_rev_onto.0` and
`@l0_f_rev_onto.1`, and a call that gives `T` the type `int` calls the
first, one that gives it `(list int)` or `Tree` the second. Within a copy,
everything sections 10.1 and 10.3 decide by a value's type is decided as if
each type parameter were a type of its kind: a block's mask, whether a value
is counted, which parameters are read-only, whether `eq` and `compare` are
instructions or runtime calls, and the `counted` that `hash` passes. Nothing else about a type
reaches the generated code, so one copy is correct for every type of its
kind, and a function needs no hidden argument saying which it was given.
That holds inside a copy only. At a call, the result has the type section
4.1 gives it from the call's arguments, `(list Pt)` where a copy's return
type says `(list int)`, and everything sections 10.1 and 10.3 decide about
the result is decided by that type: whether a value taken out of it is
counted, and the mask of a block built from it.
Each copy is a function in its own right for everything below: it has its
own tail-call component and its own read-only parameters. A compiler may
emit every copy, or only those some call reaches.

**A function with function parameters** (5.7) compiles to one function per
combination of the kinds above and of the `def` each function parameter is
given, and only to those some call reaches, which are finitely many, since
only a `def` can be given. A copy is named for the function, then its kind
digits if it takes type parameters, then one part per function parameter,
in order: a `.`, `F` for a `def` of the program or `P` for one of the
prelude, and that `def`'s name, followed by its own `.` and kind digits if
it takes type parameters, those that the call gives it. `find_by` of 5.7,
given the program's `name_of` at a counted `T` and `K`, compiles to
`@l0_f_find_by.11.Fname_of`. A copy takes only the parameters that are not
functions, in order, and a call to it passes only those arguments; a call
through a function parameter within it is a direct call of the `def` it was
given, a tail call where it is in tail position. So no function is a value
at run time, and the rest of this section and 10.3 apply to a copy as to
any function. Within a copy, the kinds of the function's type parameters
are those the call gave them, a type parameter only a function argument
determines among them, so a call through a function parameter has a result
of the right kind.

A function takes one `i64` for each L0 parameter, in order, and then enough
more to have as many as the function of greatest arity in its *tail-call
component*. A caller passes 0 for each parameter past the L0 ones, and the
function ignores them. Two functions are in the same component when one makes
a tail call to the other, in the sense of section 8, and the relation is
closed: a function in one component with either is in one with both. LLVM
guarantees a tail call only between functions of the same prototype (10.3),
and the padding is what gives every tail call one. Determining components
needs only the calls in each body, so it is a function of the input as 10.4
requires.

The program's `main` compiles to `@l0_f_main.body`, an internal function like
any other, and a call to `main` within the program calls it. The dot keeps
the symbol from colliding with any function's, since no L0 name contains one.
The runtime instead calls `i64 @l0_f_main(i64)`, which the compiler also
emits. It calls `@l0_f_main.body` with its argument, or with none for a `main`
that takes no parameters, and then the padding, and returns the result, so
that the runtime calls every `main` the same way whatever its component. A
function named `main` in the prelude is ordinary library code, compiled to
`@l0_p_main` like any other.

Only `@l0_f_main` and `@l0_main_ret_kind` require external linkage, because
those are the two names the runtime looks up. Every other function may be
emitted with internal linkage, and should be: a program is a closed module, so
internal linkage is what allows the host toolchain to delete the prelude
functions the program never calls.

A compiled program must also define:

```llvm
@l0_main_ret_kind = global i64 K
```

where K is 0 if `main` takes its input and returns `int`, 1 if `bool`, 2 if
`(list int)`, and 3 if `main` takes no parameters. The runtime reads it to
decide whether to read the input first, and what to do with the result.

Emitted IR must **not** declare a target triple or data layout. A triple is
derived from the host, and section 10.4 forbids host-derived data from reaching
the output; the same compiler run on two machines must produce the same bytes.
The host toolchain supplies the triple when it assembles the IR.

### 10.3 Runtime interface

The runtime is LLVM IR, linked into every compiled program. Its first part,
`runtime/l0rt.ll`, is the same text on every host, carries no target
triple, for the reason 10.2 gives, and is all that compiled code calls. The
**host** is the rest, the only part that reaches the machine. On an
operating system it is one file, `runtime/host-libc.ll`, which calls libc
and carries no triple either, so that it serves macOS and Linux alike.

On a machine without one, the host does what libc would, as section 9.2
says a host must, and is made of parts, so that what a CPU decides is
written once for every board with that CPU, and what a board decides once
for every program on it. A **board's host** is `runtime/bare/board.ll`,
what no machine decides, which carries no triple; its CPU's part,
`runtime/arch/ARCH/boot.ll`, which boots the CPU and names its triple; the
board's part, `runtime/board/BOARD.ll`, which says what the board has and
where, and its layout, `runtime/board/BOARD.ld`; and the drivers in
`runtime/dev/` that the board's part drives its devices with, which carry
no triple. A **process's host**, for a process of a kernel, is
`runtime/bare/proc.ll`, which makes system calls where a board's host
drives the machine, and its CPU's part, `runtime/arch/ARCH/proc.ll`; it
names no board, and `runtime/proc.ld` lays out the process. Each target
has a manifest, `runtime/targets/NAME.target`, which lists its parts.
Where there is no libc, `runtime/freestanding.ll` is linked too: an
allocator over the heap the layout gives, and what else a C environment
provides, below; it carries no triple. The program and `l0rt.ll` are the
same on every host.

There are three boards, QEMU's `virt` board for each CPU, the **virt
boards**, which `l0 build --target virt --arch ARCH` builds for, and the
Raspberry Pi 5, which `l0 build --target pi5` builds for:

- **aarch64**, whose part is `runtime/board/virt-aarch64.ll`, run with 2 GB
  of RAM. It boots by the arm64 boot protocol, Linux's, as
  `runtime/arch/aarch64/boot.ll` does on any arm64 board: a raw image with
  that protocol's 64-byte header, loaded at 0x40080000, and entered at EL2
  or EL1 with the address of the machine's device tree in `x0`; the boot
  code leaves EL2 for EL1, where the program runs, and `l0 boot` starts
  QEMU with its virtualization extension on, so that the board is entered
  at EL2 as the Raspberry Pi 5 is. Its standard
  input is the bytes QEMU's loader puts at 0x50000000, their count in the
  8-byte word at 0x4FFFFFF8, which the host reads before the program
  starts.
- **riscv64**, whose part is `runtime/board/virt-riscv64.ll`, run with
  3 GB of RAM, from 0x80000000 to 0x140000000, of which the 4th gigabyte,
  the low user range below, is never used.
  It boots by the RISC-V Linux image protocol, as
  `runtime/arch/riscv64/boot.ll` does on any riscv64 board whose firmware
  is an SBI: a raw image with that protocol's 64-byte header, loaded at
  0x80200000 by QEMU's firmware, OpenSBI, and entered in S-mode with the
  booting hart's number in `a0` and the device tree's address in `a1`.
  Its code is built for RV64GC, with the medany code model. Its standard
  input is the bytes QEMU's loader puts at 0x84000000, their count in the
  8-byte word at 0x83FFFFF8, which the host reads before the program
  starts. OpenSBI
  writes a banner on QEMU's standard output as it starts, so `l0 boot`
  gives the board's serial line a descriptor of its own, and only the
  program's bytes reach standard output.

The **Raspberry Pi 5**, whose part is `runtime/board/pi5-aarch64.ll`, is an
aarch64 board with at least 2 GB of RAM, from 0, and no emulator, so
`l0 boot` does not run it: `l0 card IMAGE DIR` writes what its SD card's
boot partition needs beside the firmware's own files, and the board's
firmware, which the program does not replace, runs it. It boots by the arm64
boot protocol as the aarch64 virt board does: the firmware loads the raw
image at 0x80000, `kernel_address` in its `config.txt`, and BL31, which
stays resident below it and holds the other three CPUs until the host
starts them (below), enters it at EL2
with the device tree's address in `x0`, from which the boot code leaves EL2
for EL1. The firmware puts the device tree at 0x08000000 and the standard
input's bytes at 0x10000000, as `l0 card`'s `config.txt` tells it. There is
no loader's word: standard input is the `initramfs` the firmware loaded,
which it describes in the device tree's `/chosen` node as `linux,initrd-start`
and `linux,initrd-end`, each of one or two cells, which the host reads
before the program starts, and without one standard input is empty. The
virt boards read the same properties first, so that QEMU's `-initrd` is
their standard input too where it lies below the heap, as it does on the
aarch64 board and does not on the riscv64 one, whose QEMU puts it inside the
heap, and take the loader's word otherwise. The debug UART, a PL011, is standard output and standard error,
which are not apart, since the board has one serial line and no semihosting;
the host drains it before the program stops. An exit with a nonzero
status writes `l0: exit status N` on it, and then the host asks the
firmware to power the board off by PSCI's `SYSTEM_OFF`, which halts it;
`board_reset` asks it for `SYSTEM_RESET` instead, which starts the board
again as at power-on. A
Pi 5 gives no more than that: the board's firmware, its mailbox, its
display and its RP1, behind PCIe, are no part of what the host drives,
but for the MSIs that PCIe's controller passes to the GIC through its
`mip0` (below), though the mailbox, the display's HVS and its IOMMU, RP1's peripherals,
and the PCIe controller they are behind are regions (below). `l0 card`'s `config.txt` says `pciex4_reset=0` too, so
that the firmware leaves the PCIe link to RP1 up, and
`hdmi_force_hotplug=1`, which asks it to bring HDMI0 up with no monitor,
though a board run shows the HVS still unreadable then (below).

The riscv64 image checks that it runs where it was linked, and spins if
not, since a loader is free to put an image elsewhere. Each image's
header's magic, at byte 56, says which CPU it is for, and for an arm64
image the reserved word at byte 48 says which board, 0 for the virt board
and 0x356970, "pi5", for the Raspberry Pi 5: `l0 boot` reads them to choose
the board, and refuses a board it has no emulator for.

**A board's layout.** A board's `BOARD.ld` is a template, which `l0
build` fills with the sizes of the program's heap and stack before it
links; the heap starts at a fixed address above where standard input is
loaded, and the stack grows down from a fixed top, so where either lies
never depends on standard input's size:

| Board | Heap from | Stack top | Default heap | Default stack | Room for both |
|---|---|---|---|---|---|
| aarch64 virt | 0x58000000 | 0xC0000000 | 1,024 MB | 256 MB | 1,664 MB |
| riscv64 virt | 0x8C000000 | 0xBC000000 | 512 MB | 256 MB | 768 MB |
| Raspberry Pi 5 | 0x40000000 | 0x80000000 | 768 MB | 256 MB | 1,024 MB |

`--heap-mb N` and `--stack-mb N`, given to `l0 build`, `l0 run`, `l0
link`, or `l0 test` with `--target virt` or `pi5`, set them in megabytes,
at least 1 each, and together at most the room the table gives, which the
driver refuses past. A program that needs little of its own, such as a
kernel, gives the rest to the frames processes are made of (below). With
`--layout FILE` the driver links with FILE, a linker script, in place of
the template: it may place the image's sections, the heap, and the stack
anywhere in the RAM the boot map reaches (below), and must define every
symbol the template does, with `__input_len` and `__input_start` where the
board's template puts them, since `l0 boot` and `l0 card` load standard
input there for any image of the board. The driver puts
`__l0_heap_size` and `__l0_stack_size`, in bytes, before either script,
the template's sizes or those the options give, so that a layout file
may size its heap and stack by them too, and checks after it that the heap
and the stack are each at least a page, aligned to one, and apart, and
that standard input is where the board's template has it. What else a
layout file gets wrong, the board does: an image overlapping its device
tree, or a heap past its RAM, fails as the board fails. Other targets
take none of the three options: a process's layout is fixed, since its
kernel maps it (below), and an operating system's host gives its own.

`l0rt.ll` provides exactly these functions:

```llvm
declare i64 @l0_cons(i64, i64)
declare i64 @l0_head(i64)
declare i64 @l0_tail(i64)
declare i64 @l0_is_empty(i64)
declare i64 @l0_div(i64, i64)
declare i64 @l0_mod(i64, i64)
declare i64 @l0_data_new(i64, i64)
declare void @l0_data_set(i64, i64, i64)
declare i64 @l0_data_tag(i64)
declare i64 @l0_data_get(i64, i64)
declare void @l0_stack_check()
declare i64 @l0_read_byte()
declare i64 @l0_write_byte(i64)
declare void @l0_inc(i64)
declare void @l0_dec(i64)
declare i64 @l0_new_cons(i64, i64, i64)
declare i64 @l0_string(ptr, i64)
declare i64 @l0_new_data(i64, i64, i64)
declare i64 @l0_read_from(i64)
declare i64 @l0_write_to(i64, i64)
declare i64 @l0_open_read(i64)
declare i64 @l0_open_write(i64)
declare i64 @l0_close(i64)
declare i64 @l0_arg_count()
declare i64 @l0_arg(i64)
declare i64 @l0_flush(i64)
declare i64 @l0_open_append(i64)
declare i64 @l0_rename(i64, i64)
declare i64 @l0_open_bytes(i64)
declare i64 @l0_open_buffer()
declare i64 @l0_buffer_bytes(i64)
declare i64 @l0_array_new(i64, i64, i64)
declare i64 @l0_array_len(i64)
declare i64 @l0_array_get(i64, i64)
declare i64 @l0_array_set(i64, i64, i64)
declare i64 @l0_array_set_row(i64, i64, i64, i64)
declare i64 @l0_read_bytes(i64)
declare i64 @l0_bytes_len(i64)
declare i64 @l0_bytes_get(i64, i64)
declare i64 @l0_bytes_from_list(i64)
declare i64 @l0_bytes_to_list(i64)
declare i64 @l0_write_bytes(i64, i64, i64, i64)
declare i64 @l0_clock_ns()
declare i64 @l0_equal(i64, i64)
declare i64 @l0_hash(i64, i64)
declare i64 @l0_bit_shl(i64, i64)
declare i64 @l0_bit_shr(i64, i64)
declare i64 @l0_bit_count(i64)
declare i64 @l0_remove(i64)
declare i64 @l0_compare(i64, i64)
declare i64 @l0_read_some(i64, i64)
declare i64 @l0_region_open(i64, i64)
declare i64 @l0_region_close(i64)
declare i64 @l0_region_read8(i64, i64)
declare i64 @l0_region_read16(i64, i64)
declare i64 @l0_region_read32(i64, i64)
declare i64 @l0_region_read64(i64, i64)
declare i64 @l0_region_write8(i64, i64, i64)
declare i64 @l0_region_write16(i64, i64, i64)
declare i64 @l0_region_write32(i64, i64, i64)
declare i64 @l0_region_write64(i64, i64, i64)
declare i64 @l0_region_read_bytes(i64, i64, i64)
declare i64 @l0_region_write_bytes(i64, i64, i64, i64, i64)
declare i64 @l0_barrier()
declare i64 @l0_array_take(i64, i64)
declare i64 @l0_space_new()
declare i64 @l0_frame_new()
declare i64 @l0_space_map(i64, i64, i64, i64)
declare i64 @l0_space_map_device(i64, i64, i64, i64)
declare i64 @l0_space_read(i64, i64, i64)
declare i64 @l0_space_write(i64, i64, i64, i64, i64)
declare i64 @l0_user_run(i64, i64)
declare i64 @l0_timer_at(i64)
declare i64 @l0_interrupt_enable(i64)
declare i64 @l0_interrupt_wait()
declare i64 @l0_interrupt_done(i64)
declare i64 @l0_supervisor_call(i64, i64, i64, i64)
declare i64 @l0_supervisor_send(i64, i64, i64, i64, i64)
declare i64 @l0_supervisor_receive(i64, i64, i64)
declare i64 @l0_frame_address(i64)
declare i64 @l0_space_unmap(i64, i64)
declare i64 @l0_space_free(i64)
declare i64 @l0_frame_free(i64)
declare i64 @l0_machine()
declare i64 @l0_frame_free_count()
declare i64 @l0_frame_sync(i64, i64)
declare i64 @l0_bytes_slice(i64, i64, i64)
declare i64 @l0_bytes_concat(i64)
declare i64 @l0_board_reset()
declare i64 @l0_cpu_count()
declare i64 @l0_cpu_run(i64, i64, i64, i64, i64)
declare i64 @l0_cpu_trapped()
declare i64 @l0_cpu_wait()
declare i64 @l0_heap_left()
declare i64 @l0_data_with(i64, i64, i64)
declare i64 @l0_data_take(i64, i64)
```

**The host interface.** `l0rt.ll` calls nothing outside itself but these
functions of the host, and `memcpy`, `memmove`, `memset`, and
`memcmp`, which every C environment provides, with an operating system or
without one, and which LLVM may call for its own memory intrinsics anyway.
Where nothing else provides them, `freestanding.ll` defines them, and
`bcmp` and `strlen`, which LLVM may make of a `memcmp` and of a loop that
finds a NUL, as `l0rt.ll`'s do for a path or an argument; it also defines
`alloc`, `alloc_aligned`, `resize`, and `free` below for a board's host
and a process's, over the heap from `__heap_start` to `__heap_end` that
their layouts give:

```llvm
declare ptr @l0_host_alloc(i64)
declare ptr @l0_host_alloc_aligned(i64, i64)
declare ptr @l0_host_resize(ptr, i64)
declare void @l0_host_free(ptr)
declare i64 @l0_host_read(i64, ptr, i64)
declare i64 @l0_host_write(i64, ptr, i64)
declare i64 @l0_host_open(ptr, i64)
declare i64 @l0_host_close(i64)
declare i64 @l0_host_rename(ptr, ptr)
declare i64 @l0_host_remove(ptr)
declare i64 @l0_host_clock_ns()
declare i64 @l0_host_board_reset()
declare i64 @l0_host_arg_count()
declare ptr @l0_host_arg(i64)
declare ptr @l0_host_setting(ptr)
declare void @l0_host_exit(i64) noreturn
declare i64 @l0_host_region(i64, i64)
declare void @l0_host_region_close(i64, i64)
declare void @l0_host_barrier()
declare i64 @l0_host_space_new()
declare i64 @l0_host_frame_new()
declare i64 @l0_host_frame_address(i64)
declare i64 @l0_host_frame_sync(i64, i64)
declare i64 @l0_host_space_map(i64, i64, i64, i64)
declare i64 @l0_host_space_map_device(i64, i64, i64, i64)
declare i64 @l0_host_space_unmap(i64, i64)
declare i64 @l0_host_space_free(i64)
declare i64 @l0_host_frame_free(i64)
declare i64 @l0_host_frame_free_count()
declare i64 @l0_host_space_copy(i64, i64, ptr, i64, i64)
declare i64 @l0_host_user_run(i64, ptr, i64)
declare i64 @l0_host_timer_at(i64)
declare i64 @l0_host_interrupt_enable(i64)
declare i64 @l0_host_interrupt_wait()
declare i64 @l0_host_interrupt_done(i64)
declare i64 @l0_host_supervisor(i64, i64, i64, i64)
declare i64 @l0_host_machine()
declare i64 @l0_host_cpu_count()
declare i64 @l0_host_cpu_run(i64, i64, ptr, i64, i64, i64)
declare i64 @l0_host_cpu_trapped(ptr)
declare i64 @l0_host_cpu_wait()
declare i64 @l0_host_heap_left()
```

Every result that can fail is a section 6.3 code, so the host, not
`l0rt.ll`, knows how its own failures are told apart.

- `alloc`, `resize`, and `free` keep `malloc`'s, `realloc`'s, and `free`'s
  contracts; null means memory is exhausted. `l0_host_alloc_aligned(align,
  n)` keeps `posix_memalign`'s, for an `align` that is a power of two, and
  returns the block or null; what it gives is freed with `free`.
  `freestanding.ll`'s gives a block `l0_host_alloc` would give, when that
  is aligned, so blocks asked for 64 bytes or more under `align` lie end to
  end as far as the heap allows. `l0_host_heap_left()` returns how many
  bytes the host's heap has in free blocks, headers and footers included,
  not less than 0, as `freestanding.ll`'s does, or -3 where the heap is an
  operating system's, as `host-libc.ll`'s does.
- A **stream** is an integer the host chooses. 0, 1, and 2 are standard
  input, output, and error, open from the start, and open on nothing where
  section 9.2 says so; `open` gives any other. `l0_host_read(s, buf, n)`
  reads at most `n` bytes, waiting only while none has arrived, and returns
  how many, 0 at end of input, or -5. `l0_host_write(s, buf, n)` writes at
  least one of `n` bytes and returns how many, or -5, -6, or -7.
  `l0_host_close(s)` returns 0, or -5, -6, or -7 as a write would.
- `l0_host_open(path, mode)` opens as `open_read` does for mode 1, as
  `open_write` for mode 2, and as `open_append` for mode 3, and returns a
  stream or that builtin's code. `l0_host_rename` and `l0_host_remove`
  return what `rename` and `remove` do. A path is NUL-terminated, so a path
  holding a zero byte is -5 before the host sees it.
- `l0_host_clock_ns` is section 6.7's `clock_ns`. `l0_host_arg_count`
  counts the arguments, not the program's name, and `l0_host_arg(i)` is
  argument `i`, NUL-terminated. `l0_host_setting(name)` is the
  environment's value for `name`, NUL-terminated, or null if it is unset or
  there is no environment. A board's host's arguments are its boot
  arguments: the `bootargs` property of the device tree's `/chosen` node,
  which QEMU sets from `-append` and a board's firmware from its own
  configuration, split at each run of spaces, so no argument holds a
  space and none is empty, and there are none if the property is missing
  or blank. The program's arguments are those after the last that is
  `--l0-args`, and all of them if none is, so that a firmware's own can be
  told from the program's: the Raspberry Pi's puts 17 of its own before
  those of `cmdline.txt` (the changelog's "The Raspberry Pi 5's firmware
  puts its arguments first"), and `l0 card` writes `--l0-args` first in
  `cmdline.txt`. The marker is never one of the arguments given, and an
  argument before the last marker is none of the program's, whatever it
  is. It copies them out before the program starts, while nothing
  else has touched memory, since the boot protocol puts the device tree
  wherever the firmware chose: QEMU, at 0x48000000 on the aarch64 board
  and 0xBFE00000 on the riscv64 one, and the Raspberry Pi's firmware, at
  0x08000000, where `l0 card`'s `config.txt` puts it, with `cmdline.txt` as
  `bootargs`, which that firmware puts its own arguments before.
  At most 65,536 bytes
  of them are read, and at most 4,096 arguments, counting the marker and
  those before it. It has no program name
  among them, and no environment.
- `l0_host_machine()` is section 6.16's `machine`. `host-libc.ll` gives 0,
  since it carries no triple and serves every CPU alike, and every other
  host the number of the CPU its CPU's part is for: 1 from
  `runtime/arch/aarch64/` and 2 from `runtime/arch/riscv64/`.
- `l0_host_exit(status)` stops the program at once with that status.
  Whatever was held back has been delivered by then.
- `l0_host_board_reset()` is section 6.12's `board_reset`. It asks the
  board's firmware to reset it by PSCI's `SYSTEM_RESET`, function
  0x84000009, by SMC, after the serial line is drained, and does not
  return, on the Raspberry Pi 5, where the firmware's bootloader then
  starts as at power-on, and on the aarch64 virt board, where QEMU resets
  the machine, or exits with status 0 if it was run with `-no-reboot`, as
  `l0 boot` runs it. It returns -3 from `host-libc.ll`, from a process's
  host, and on the riscv64 virt board.
- `l0_host_region(base, len)` is the address at which the program reads
  and writes the `len` bytes of device memory at `base`, mapped so that
  every access reaches the device at its width and in order, or -3 if the
  host gives no region there. `l0rt.ll` checks `base` and `len` first,
  keeps the table of open regions, and checks every access against it.
  `l0_host_region_close(addr, len)` undoes what `l0_host_region` did when
  it gave `addr` for those `len` bytes, after which the program never
  touches them; `l0rt.ll` calls it for a region `region_close` closes,
  after the barrier, and for an address it was given but has no room in
  its table for, before giving -5. A host that mapped nothing for a region
  does nothing, as `host-libc.ll`, which gives none, and a board's host,
  whose regions are the devices' own addresses, do.
  `l0_host_barrier()` is section 6.12's `barrier`. `host-libc.ll` gives -3
  for every range, and its barrier is a fence. A board's host gives a
  region over any range wholly within one of the board's devices, at the
  address it names, where every access reaches the device at its width and
  in order and nothing is merged, reordered, or written back early: on the
  aarch64 boards because their boot map makes the range device memory,
  Device-nGnRnE, and their barrier is `dsb sy`; on the riscv64 board because
  the board's physical memory attributes make it I/O, and its barrier is
  `fence iorw, iorw`. A device takes the widths it takes: the 16550's
  registers are bytes, and a wider access to one is a fault. Each board's
  devices, what the host sets up of them, and what a board run found of
  them, are in its file: [boards/virt-aarch64.md](boards/virt-aarch64.md),
  [boards/virt-riscv64.md](boards/virt-riscv64.md), and
  [boards/pi5.md](boards/pi5.md).

  `l0 boot` starts QEMU with the transports modern, version 2 of the
  virtio-mmio interface, whose queues are each three areas a device finds
  at addresses of their own, each of which a frame holds, rather than
  legacy, whose queue is one area, which for more than a few entries spans
  frames that would have to lie next to each other.

  A process's host asks its kernel, by the region system call of
  [boards/process.md](boards/process.md).
- The user-mode builtins of section 6.13 are `l0rt.ll`'s calls of the
  `l0_host_space_`, `frame_`, and `user_run` functions, which keep the
  spaces, the frames, and everything about them. `l0_host_space_new` and
  `l0_host_frame_new` return what the builtins do. The others check in
  section 6.13's order and return 0 or a code, and `l0rt.ll` raises the
  runtime error a positive code names: 1 `not a space`, 2 `not a frame`, 3
  `page permissions out of range`, 4 `not a user page`, 5 `user page
  already mapped`, 6 `user memory not mapped`, 7 `not a context`, 9
  `frame still mapped`, 10 `user page not mapped`, 12 `space still
  running`; 8 is section 6.14's, and 11 section 6.18's.
  `l0_host_frame_address(f)` returns what `frame_address` does, or 2,
  which is never an address, since an address is a multiple of 4096.
  For `frame_sync`, `l0rt.ll` first asks for the frame's address, which
  says whether `f` is a frame, then checks `dir` itself, then calls
  `l0_host_frame_sync(f, dir)`, which syncs and returns 0, or 2.
  `l0_host_space_unmap(s, va)`, `l0_host_space_free(s)`, and
  `l0_host_frame_free(f)` return 0 or a code.
  `l0_host_frame_free_count()` returns what `frame_free_count` does.
  `l0_host_space_map` and `l0_host_space_map_device` return -5, and the
  latter -3, where the builtins do. For
  `space_read` and `space_write`, `l0rt.ll` first asks for an empty copy,
  which only says whether `s` is a space, then checks the count or the
  range of bytes itself, then asks for the copy.
  `l0_host_space_copy(s, va, buf, n, dir)` copies `n` bytes between `buf`
  and space `s` from `va`, into the space if `dir` is 1 and out of it if 0.
  `l0_host_user_run(s, words, n)` runs the thread whose context is the `n`
  words at `words`, and writes them back at its trap. `host-libc.ll` and
  a process's host have no user mode: -3 for a new space or frame and for
  the count, 2 for a frame's address or syncing or freeing a frame, and 1 for
  anything else. The virt
  boards' hosts and the Raspberry Pi 5's have it, the aarch64 ones at EL1
  with their threads at EL0, the riscv64 one in S-mode with its threads in
  U-mode, and give:

  - the user range, in two parts: the **low user range**, 0xC0000000 up
    to 0x100000000, the 4th gigabyte, and the **high user range**,
    0x2000000000 up to 0x4000000000, the 129th to the 256th gigabyte,
    128 GB. Each space maps their pages for its threads alone, with the
    board's own map around them reachable only by the host, so a thread
    that touches the program's memory faults. No board's map uses the high
    part, whose end is where Sv39's lower half ends and below where the
    aarch64 board's PCIe ECAM begins, and a space takes the tables for it
    only as pages there are mapped. A copy by `space_read` or
    `space_write` lies within one part, as their pages do, since the
    addresses between the parts are none of the space's
  - frames and the host's page tables from a pool: the RAM the device
    tree's `/memory` nodes describe that lies in the board's **frame
    windows**, less the device tree itself and the pages holding
    standard input's bytes. The windows are the RAM the boot map reaches,
    less everything below the image's end, the heap, and the stack, as
    the layout places them: on the aarch64 board from 0x40000000 up to
    0xC0000000, the low user range's start; on the riscv64 board from
    0x80000000 up to 0xC0000000, and from 0x100000000 up to 0x140000000,
    past the low user range; on the Raspberry Pi 5 from 0 up to
    0xC0000000, and from 0x100000000 up to 0x400000000. So the RAM the
    board's `/memory` nodes describe is the pool but for the image and
    what lies below it, the firmware's among it, the heap, the stack, the
    low user range, and what the firmware keeps out of those nodes; no
    board has RAM in the high one. With the
    default sizes the pool is about 765 MB on the aarch64 board at 2 GB
    and about 1.2 GB on the riscv64 board at 3 GB; with a heap of 64 MB
    and a stack of 16 MB, about 1,967 MB and about 1,965 MB. The Pi's
    boot map maps only the RAM those nodes describe, 1 GB at a time, and
    its 2 GB model is the least it runs on. RAM past the windows is not
    used. The pages holding standard
    input's bytes join the pool once a read of standard input has reached
    its last byte, since no read can give those bytes again, and with no
    input, at once; the count of `frame_free_count` grows then by those
    pages. The host keeps 4 bytes for each page of the pool in its first
    pages, so it has as many frames as the RAM allows, with no bound of
    its own. A frame's number is the host's: frames are numbered through
    the pool's pages in an order of the host's choosing, and nothing but
    `frame_address` says where one is. A page given back, as a frame or
    as a table, serves again as either. Spaces
    up to 255 at once, each with an ASID of its own, so moving between them
    flushes nothing, on a riscv64 hart with fewer than 8 ASID bits every
    space has ASID 0, and moving to one flushes; a space given back gives
    its ASID with its number, and its entries are flushed from the TLB
    first, as an unmapped page's is. The frames are mapped as normal
    memory, write-back, and device pages as regions are. A page is
    zeroed, for a frame or a table, in the cache: on the aarch64 hosts by
    `dc zva`, a block at a time of the size `DCZID_EL0` gives, unless it
    says that is prohibited, and then by stores, as on riscv64, so no line
    is read from memory only to be overwritten
  - a frame's address that is its physical address in that pool. The virt
    boards' devices reach memory as their CPU does, through the same
    caches, so what a device writes into a frame is what a `space_read`
    after a `barrier` copies, and what `space_write` copied before a
    `barrier` is what the device reads. The Raspberry Pi 5's do not:
    its DMA is not coherent with the CPU's caches, so on that board a
    device reading or writing a frame sees the memory's bytes, which are
    the cache's only after a `frame_sync` (6.13)
  - a `frame_sync` that on the aarch64 hosts is `dc cvac` for 1, `dc
    ivac` for 2, or `dc civac` for 3, over the frame's 4096 bytes in the
    host's own map, a line at a time, the least line `CTR_EL0` says, and
    then `dsb sy`. A thread's mapping of a frame reaches the same
    physical address with the same attributes, and the data caches are
    physically tagged, so this covers what a thread wrote too. On the
    virt boards, whose devices are coherent and whose CPU QEMU models
    without caches, it changes nothing but as the barrier; on the riscv64
    one it is the barrier, `fence iorw, iorw`, and no more
  - copies that reach only frames, so a device page is no memory
    `space_read` and `space_write` can reach
  - a context of 104 words, laid out for each CPU as follows. On both,
    word 32 is where the thread resumes, word 35 the trap, 0 an exception,
    a system call or a fault, or 1 an interrupt, word 36 what the CPU said
    of an exception or the interrupt's number (6.14), and word 37 the
    address that faulted. On aarch64 a thread runs at EL0 with interrupts
    unmasked whatever word 33 says beyond its flags, and may read the
    virtual counter, so the process host's clock works (below)

    | Words | Register |
    | --- | --- |
    | 0 to 30 | `x0` to `x30` |
    | 31 | `sp`, the thread's stack pointer |
    | 32 | `pc`, where the thread resumes: after its `svc`, at the instruction that faulted |
    | 33 | `pstate`: only the flags, bits 28 to 31, are the thread's |
    | 34 | `tpidr_el0` |
    | 35 | the trap |
    | 36 | `ESR_EL1`, the exception's syndrome, or the interrupt's number |
    | 37 | `FAR_EL1`, the address that faulted, or 0 |
    | 38 to 101 | `q0` to `q31`, two words each, the low one first |
    | 102 | `fpcr` |
    | 103 | `fpsr` |

    and on riscv64 a thread runs in U-mode with interrupts on, and may
    read the time, whose rate it cannot know, so the process host's clock
    is a system call (below)

    | Words | Register |
    | --- | --- |
    | 0 | nothing: `x0` is 0 |
    | 1 to 31 | `x1` to `x31`, the stack pointer, `sp`, being `x2` |
    | 32 | `pc`, where the thread resumes: after its `ecall`, at the instruction that faulted |
    | 33 | 0 |
    | 34 | 1 after a page fault where nothing is mapped, which the CPU does not tell from one a page's permissions make, else 0 |
    | 35 | the trap |
    | 36 | `scause`, the exception's cause, or the interrupt's number |
    | 37 | `stval`, the address that faulted, or 0 |
    | 38 to 69 | `f0` to `f31` |
    | 70 | `fcsr` |
    | 71 to 103 | 0 |

    The library's `call_number`, `call_arg`, `call_result`, and
    `trap_of` (6.13) read the words where each CPU puts them.
- The interrupt builtins of section 6.14 are `l0rt.ll`'s calls of the
  `l0_host_timer_at` and `l0_host_interrupt_` functions, which return
  what the builtins do; `l0_host_interrupt_done` returns 0 or 8, which
  `l0rt.ll` raises as `interrupt not taken`. `host-libc.ll` and
  a process's host have no interrupts: -3, and 8 for `interrupt_done`.
  A board's host drives its interrupt controller itself, so it is no
  region, and gives the interrupts its board's file lists, under
  "Interrupts".
- The builtins of section 6.18 are `l0rt.ll`'s calls of the
  `l0_host_cpu_` functions. `l0_host_cpu_count()` returns what
  `cpu_count` does. `l0_host_cpu_run(c, s, words, n, deadline, tag)`
  copies the context of `n` words at `words` and hands it over, checking
  in section 6.18's order, and returns 0, -5, or a code, 11 `not a CPU`,
  1 `not a space`, or 7 `not a context`, which `l0rt.ll` raises.
  `l0_host_cpu_trapped(out)` with a null `out` returns 1 if a CPU has a
  thread to give back and 0 if none does, taking nothing, and otherwise
  takes back the one `cpu_trapped` gives, writing its context's words,
  its CPU, and its tag at `out`, and returns 1; `l0rt.ll` asks first, and
  builds the array only for a thread there is. `l0_host_cpu_wait()`
  returns what `cpu_wait` does. `host-libc.ll`, a process's host, and
  the riscv64 virt board's host run threads on no other CPU: 1, 11, 0,
  and what `l0_host_interrupt_wait` returns. The aarch64 boards' hosts
  run them on the CPUs their device tree lists, at most 8 in all:
  - as the program starts, the host reads the device tree's `/cpus`, and
    each node in it whose `device_type` is `cpu` and whose
    `enable-method` is `psci`, but the booting CPU's, whose `reg` is its
    own `MPIDR_EL1`'s affinity, it starts by PSCI's `CPU_ON`, function
    0xC4000003, by SMC, in the order the tree lists them, numbering them
    from 1. It counts one once the CPU has said it runs, and stops at the
    first that the firmware refuses or that has not said so within 100
    milliseconds. QEMU's virt board, run with `-smp N`, which `l0 boot`
    gives when `L0_QEMU_ARGS` says so, lists its N CPUs so, and the
    Raspberry Pi 5's firmware its four.
  - a CPU it starts boots as the booting CPU does, to EL1 with the boot
    map, and its interrupts masked, and then runs the threads handed to
    it at EL0, with interrupts unmasked, in a loop of the host's that
    touches no memory of the program's. Each CPU has a ring of 4 slots,
    each holding a context and what runs it: `cpu_run` writes a slot and
    publishes it with a release store, and the CPU takes it with an
    acquire load, runs it, writes the context back into the slot, and
    publishes that the same way, so the ring needs no lock and no
    compare-and-swap. A CPU with an empty ring polls it for 100
    microseconds of the generic timer's count, and then says in its ring
    that it sleeps, by a sequentially consistent store, looks once more,
    and waits by `wfi`, its interrupts masked; `cpu_run`, after its own
    sequentially consistent store of the handed count, reads that word,
    and sends a CPU that sleeps the GIC's SGI 0, through `GICD_SGIR`, to
    the CPU interface the CPU read from its banked `GICD_ITARGETSR0` as
    it started. So a CPU busy with threads, or briefly between them, is
    sent nothing, and one that sleeps cannot miss its thread. A CPU
    leaves each thread's tables for the boot map before it publishes its
    trap.
  - each CPU's timer is its own virtual timer, the GIC's PPI 27, which
    the CPU enables and takes in its own banked registers, and ends and
    disarms before it publishes the thread's trap. Every device's
    interrupt goes to CPU 0 alone, as the GIC's targets say. `cpu_wait`
    polls the rings, and the GIC's acknowledge register whenever
    `ISR_EL1` says an interrupt is pending, for 100 microseconds, and
    then sleeps as another CPU does, in a word of its own: a device's
    interrupt ends its `wfi` as it ends `interrupt_wait`'s, and a CPU
    that publishes a trap while CPU 0 sleeps sends it SGI 0. An SGI the
    GIC signals is the host's alone: its driver ends it as it takes it,
    and gives it as a spurious interrupt, on every CPU, wherever it
    comes.
  - `space_unmap` invalidates the page on every CPU, by `tlbi vae1is`,
    and `space_free` the whole of every CPU's TLB, as they do already,
    and bytes `space_write` copies are made fit to run on every CPU, by
    `ic ialluis`. A table of pages is zeroed before a walk on any CPU can
    reach it.

**A process's host** runs a program as a process of a kernel, through
system calls; [boards/process.md](boards/process.md) specifies it: its
calls, its image, and its layout.

The host defines the entry point, and calls `@l0_rt_run(i64 size)`,
which `l0rt.ll` defines, on a stack with `size` bytes below the calling
frame. It does what section 9 describes for the form of `main` that
`@l0_main_ret_kind` names: reads standard input first or not, calls
`@l0_f_main`, writes the result, and returns the exit status. `host-libc.ll`
calls it on a thread with a large stack, 512 megabytes unless `L0_STACK_MB`
in the environment gives another size in megabytes, since recursion that is
not through tail calls is still how L0 walks a tree or builds a list in
order. On a host that cannot make that thread, it runs on the stack the host
gave it, at the host's size. A board's host and a process's call it on
the stack their layouts give, less 64 kilobytes for what lies above the
call: a process's 256 megabytes, and a board's what `--stack-mb` gives, 256
megabytes by default.

Each builtin of sections 6.2 to 6.4, 6.6, 6.7, 6.12 to 6.16, and 6.18 is the runtime call
of the same name with `l0_` in front, taking and returning `i64`. A path is passed as the
list it is, and `@l0_arg`, `@l0_buffer_bytes`, and `@l0_bytes_to_list` return
a list they build. `@l0_region_read_bytes`, `@l0_space_read`, `@l0_supervisor_receive`, `@l0_bytes_slice`,
and `@l0_bytes_concat` return bytes they build, and
`@l0_user_run` the context it was given if nothing else held it, and
otherwise a copy, as `@l0_array_set` returns its array; `@l0_cpu_trapped`
returns an array it builds.
`@l0_open_bytes` takes a reference of its own to the list it is given, and
releases it when the handle is closed or the program ends. The runtime buffers every handle,
and flushes standard output and standard error whenever it is about to wait
for input or an interrupt, and every handle before the process exits, including from a
runtime error, which is what sections 6.2 and 6.3 require. It remembers, for
each handle, whether a write to it failed and why, and whether `flush` or `close` has
said so since, and after the last flush at a normal exit it reports a failure
no one was told of as the runtime error of section 8.

Every compiled function, in the program and in the prelude alike, calls
`@l0_stack_check` before anything else. It reports stack exhaustion as the
runtime error of section 8 when the stack is nearly used up. The check is
explicit, rather than a handler for the fault that running off the stack
would raise, because catching that fault needs structures and constants that
differ between operating systems, and `l0rt.ll` has to be the same text on
all of them.

A tail call, in the sense of section 8, is emitted as a `musttail call`
followed immediately by a `ret` of its result, so an `if` or `match` in tail
position returns from each branch rather than joining after them. `musttail`
obliges LLVM to reuse the caller's frame at every optimization level or to
refuse the program, so a host whose toolchain cannot honor a tail call fails
when the program is built, never by exhausting the stack as it runs. It is
also why every tail call needs caller and callee to share a prototype, which
10.2's padding provides.

A tail call whose words do not all fit in the target's argument registers
passes the rest on the stack, in the caller's own incoming words, and
LLVM 23's RISC-V back end writes them into the caller's frame instead,
which the call then frees, so the callee reads stale words. The fast
calling convention passes 13 words in registers on riscv64, against the C
convention's 8, which is why 10.2 uses it, and a riscv64 target refuses,
when the program is built, a program with a tail call of more than 13
words, rather than build one that is wrong. aarch64 passes 8 in registers
under either convention, and gets the stack's words right.

The builtins that can fail at runtime — `head`, `tail`, `div`, `mod`, the
array builtins, `bytes_get`, `write_bytes`, `bytes_slice`, `read_some`, the region reads,
writes, and close, the user-mode, interrupt, and kernel-call builtins, `bit_shl`, and `bit_shr` — are runtime calls, so generated code contains no error checking
at all; so are `is_empty`, as `@l0_is_empty`, `bit_count`, as
`@l0_bit_count`, and `cons`, as `@l0_new_cons`. The shifts are calls for a
second reason: an LLVM shift by 64 or more is poison, and 6.10 gives it a
value. `eq`, `hash`, and `compare` are described below. The remaining
builtins are plain LLVM instructions: `add`, `sub`, `mul` map to `add`,
`sub`, `mul`; `neg` to `sub i64 0, x`; the comparisons to `icmp slt/sle/
sgt/sge/eq` followed by `zext i1 to i64`; `not` to `xor i64 x, 1`;
`bit_and`, `bit_or`, `bit_xor` to `and`, `or`, `xor`. `(and a b)` is
emitted as `(if a b false)` and `(or a b)` as `(if a true b)` would be,
except that `b` is never in tail position (section 8), so a call there is
never a tail call and the tail-call components of 10.2 are unchanged.
`eq` is that `icmp eq` when its arguments are `int` or `bool`, and otherwise
a call of `@l0_equal`, which returns 0 or 1.

`@l0_equal(a, b)` compares two counted values of one type as section 6.8
says, from their blocks alone: the masks of 10.1 say which words are
pointers to compare in turn and which are compared as they are, a size of 0
says the block is an array or, with mask bit 1, bytes, and the empty list,
0, is the only value that is not a block. It answers at once when `a` and
`b` are the same block, keeps the pairs of blocks still to compare on a list
of its own rather than recursing, and allocates nothing a program can see.
The blocks that `l0_data_new` makes have mask 0 whatever their fields, so
`@l0_equal`, `@l0_hash`, and `@l0_compare` are never given one: only code an
older compiler emitted makes them, and that code never calls them.

`hash` is always a call of `@l0_hash(x, counted)`, where `counted` is 1 when
`x` is a list, data, an array, or bytes and 0 when it is an `int` or `bool`,
since a word alone does not say which. `@l0_hash` computes section 6.9's
hash by walking the value as `@l0_equal` does, from its blocks alone: a word
the mask marks as a pointer contributes the items of the block it points
to, or the item 0 if it is the empty list; any other word of a cons cell or
data block contributes itself, which is how the words past a narrower
constructor's fields contribute their 0; an array contributes its length
and then its elements, and bytes their length and then their bytes. It
keeps the words still to visit on a list of its own rather than recursing,
and allocates nothing a program can see.

`compare` on two `int`s or two `bool`s is two `icmp`s, `sgt` and `slt`,
each `zext`ed, and the second subtracted from the first. On anything else it
is a call of `@l0_compare(a, b)`, which orders two counted values of one
type as section 6.11 says, from their blocks alone, walking both together
in order: a word the mask marks as a pointer is compared as the value it
points to, the empty list, 0, before any cell, and any other word of a cons
cell or data block as a signed integer, so a data block's tag, word 0,
decides first; an array compares its elements and then its length, and
bytes their bytes, unsigned, and then their length. It keeps the pairs
still to compare on a list of its own, a block's words queued last first,
so they are taken in order and the list stays as deep as the nesting, and
allocates nothing a program can see. `compare` reads its arguments without
consuming them, as `eq` does.

`l0_new_cons(head, tail, mask)` allocates a cons cell, and
`l0_new_data(tag, nfields, mask)` a block with room for `nfields` fields, each
with the layout mask of section 10.1 and a reference count of one.
`l0_string(s, n)` is a string literal's list: the `n` bytes at `s`, each
an `int` from 0 to 255, consed from the last as `n` calls of
`l0_new_cons(b, rest, 2)` would cons them. The compiler emits each
distinct non-empty literal of a module once, as a private constant array
of its bytes, numbered `@l0_str.K` in the order the literals are first
emitted, after the functions, and each use as a call of `l0_string` on
it; the empty literal is 0, the empty list.
`l0_data_set(block, index, value)` stores a field during construction.
`l0_data_tag` and `l0_data_get` read them back. `l0_cons(head, tail)` and
`l0_data_new(tag, nfields)` allocate blocks that are never freed; a compiler
does not emit them, and they remain so that code an older compiler emitted,
such as an older seed, still links and runs correctly.


**Memory is reclaimed by reference counting.** An L0 heap cannot contain a
cycle, since no mutation is observable, evaluation is strict, and `let`
cannot define a recursive value, so counting frees every block no longer
reachable and needs no collector. The one store into an existing block,
`array_set` in place, happens only when nothing else holds the array, so the
element it stores cannot hold the array either. The compiler emits the
counting:

- every value of list, data, array, or bytes type an expression produces is an
  owned reference, which its receiver consumes: a function's parameter, a
  field of a new block, a `let` binding, or the function's result
- a binding (a parameter, a `let`, or a field a `match` arm names) holds one
  reference, **until its last use on each path** through the function, not
  until its scope ends. A use of a variable of such a type that nothing
  after it on its path uses hands the binding's reference over; any earlier
  use calls `@l0_inc` on it
- a binding that a path stops needing without using it is released with
  `@l0_dec` where that happens: a parameter or `let` whose name its body
  never uses, at once; one that a branch of an `if` or `match` does not use,
  and that nothing after the `if` or `match` uses, as that branch starts. A
  field an arm does not use is never taken
- within a call or a construction, the operands that are not variables are
  evaluated first, left to right as section 8 requires, and then the
  variables are taken. Reading a variable can neither do I/O nor fail, so
  the order is unobservable except in when references are taken, and it
  makes a variable's last use as late as it can be: in `(f xs (g xs))`, the
  last use of `xs` is `f`'s
- `head`, `tail`, `is_empty`, `eq`, `hash`, `compare`, `array_len`, `array_get`,
  `open_bytes`, `bytes_len`, `bytes_get`, `write_bytes`, `bytes_slice`,
  `bytes_concat`, `region_write_bytes`, `space_write`,
  `supervisor_send`, `cpu_run`, and the builtins taking paths read their arguments
  without consuming them, and a field read `(.f e)` (5.8) reads `e` so. A variable still used later
  is read without a reference at all; any other argument is released after
  the call, in order. The compiler increments what they return, if it is a
  list, data, an array, or bytes, since that is a part of an argument,
  except what `bytes_slice` and `bytes_concat` return, which is new bytes
  with a reference of its own.
  `array_set` consumes its array and its element, as any function consumes
  its arguments, `user_run` its context, a field replacement `(.f e v)`
  (5.8) its `e` and `v`, and `bytes_from_list` and
  `bytes_to_list` consume theirs,
  since what they return is a new block rather than a part of it. A
  `match` whose subject is a variable used later reads it
  the same way, and any other subject is released once the arm has taken
  the fields it uses
- a parameter of list, data, array, or bytes type that nothing of escapes its
  function is **read-only**, and is passed the same way: a variable still
  used later without a reference, anything else released by the caller
  after the call. The function takes no reference of its own to a read-only
  parameter and never releases it. Nothing escapes when every use of the
  parameter is one of these: an argument of a builtin above that reads
  without consuming and yields no list, data, array, or bytes (`is_empty`,
  `eq`, `hash`, `compare`, `array_len`, the path builtins, `open_bytes`, `bytes_len`, `bytes_get`,
  `write_bytes`, `cpu_run`, and `head` or `array_get` of elements of int or bool
  type), a field read `(.f e)` whose type is not a list, data, array, or
  bytes type, or an argument of `bytes_slice` or `bytes_concat`, whose bytes
  are new and hold no part of it; an argument in a read-only position of another call; or the
  subject of a `match` in which every field of list, data, array, or bytes
  type that an arm names satisfies the same condition. So a
  function that keeps, returns, or updates any part of its parameter does
  not have it read-only: were the caller still to hold the parameter, that
  part would be shared, an array in it would copy on update, and a list
  walked through it would not be freed as the walk went
- such a field, of a `match` on a read-only parameter, is bound read-only
  too, without a reference, since the parameter keeps it alive for the
  whole call
- a function with type parameters is judged once per copy (10.2), since
  whether `(head xs)` yields a pointer depends on what `T` stands for
- every tail call to a function passes, in each read-only position, a
  read-only parameter or read-only field of the calling function, since
  anything else would have to be released after the call, which would take
  it out of tail position; a parameter any tail call gives something else is
  not read-only. The compiler works all this out for the whole program, and
  nothing marks it in the source. A `main`'s parameter is never read-only
- in tail position nothing is used afterwards, so every binding has been
  handed over or released by the time the final call or value is ready,
  and nothing follows a call but returning its result, which is what lets it
  be a tail call

These are guarantees, not freedoms, since what a program holds depends on
them. So a block is freed no later than the last use of the last binding
that held it, where passing it to a read-only parameter is a use that lasts
until the call returns, and a loop in tail position frees what each
iteration no longer needs before the next begins. A program that streams, allocating per
line, runs in constant memory however long its input, since its loop is tail
calls and section 8 makes those use no stack. A program whose `main` takes its
input has all of it in memory, as a list of one cons cell per byte, before
`main` starts, whatever `main` then frees.

`@l0_dec` frees a block whose count reaches zero, and every block it alone
kept alive, without recursion, and puts them on free lists by size, which
allocation takes from before it cuts a new block. Cons cells and data
blocks are cut from chunks of 1 MiB less 64 bytes, from
`l0_host_alloc_aligned` and aligned to 1 MiB, so a block's chunk is its
address with the low 20 bits cleared; the 64 bytes leave room for what a
host's allocator keeps beside a block, so chunks can lie end to end. A
chunk, other than the one being cut, whose every block is on a free list
is given back by the next sweep, which takes those blocks off their lists.
A sweep runs as a chunk is made, once the chunks made since the last sweep
are a quarter of all there are, and whenever `l0_host_alloc` or
`l0_host_resize` has no memory, before the runtime asks again; that sweep
holds nothing back, giving back the chunk being cut too, if it can. The
runtime keeps up to 4 chunks given back, to make chunks from, and gives
any more back with `l0_host_free`. So what a program frees serves later
blocks of any size, and arrays and bytes, once its chunks are given back,
and a heap without an operating system beneath it can hold one shape of
data and then another. The only count kept as blocks come and go is of
the bytes on the free lists, one addition as a block goes on one and one
subtraction as it comes off, so allocation and freeing cost what they did
with a single arena, and a sweep walks every free list. A chunk is given
back only once every block in it is freed, so one live block keeps its
chunk. `l0_heap_left()` is -3 if `l0_host_heap_left()` is, and otherwise
that, and the bytes on the free lists, and those of the chunk being cut
that are not yet cut, and 1 MiB less 64 bytes for each chunk kept to make
chunks from. So it never sweeps, and a chunk a sweep gives back counts no
less after than before: as its blocks on the free lists, and then whole,
as a chunk kept or as the host's. A count that reaches
its maximum
stays there and the block is never freed, which is also how `l0_cons` and
`l0_data_new` mark their blocks. A program reaches it only by holding one
block 2^24 − 1 times at once, which `array_new` of that many copies of one
list or data value does; that value is then never freed.

`l0_array_new(n, x, p)` allocates an array of `n` copies of `x`, taking over
`x`'s reference and adding `n − 1` more, where `p` is the mask of section
10.1. `l0_array_set(a, i, x)` stores in place when `a`'s count is 1, releasing
the element it replaces, and otherwise copies `a`, adding a reference to each
element it keeps, and releases `a`. `l0_array_set_row(g, y, x, v)` is the
form of section 6.5 that updates a row within an array of rows: it makes
`g` its own if another holds it, as `l0_array_set` does, then makes row `y`
its own the same way, stores `v` at `x` in it, and returns `g`. The compiler
checks `y` with `l0_array_get` before it evaluates `x` and `v`, so errors
come in the order the written form gives. For the form of 6.5 with any
other `f`, and an element type that is counted, the compiler emits the
argument `(array_get g y)` as `l0_array_take(g, y)`, where it stands among
`f`'s arguments, and the rest as written: `l0_array_take` checks `y` as
`l0_array_get` does, and then, when `g`'s count is 1, moves the element out,
leaving 0 in its place, and otherwise adds a reference to it; either way it
returns the element with a reference the caller owns, and allocates
nothing, so neither the order of errors nor when memory is taken differs
from the plain reading. The outer `array_set` then stores `f`'s result in
`g`, releasing the 0, which `@l0_dec` takes as the empty list. While `f`
runs, `g` holds a 0 where an element was, which nothing can read: `g` is
one variable, which no other argument mentions, and which the outer
`array_set` takes after `f` returns. `l0_data_with(b, i, x)` is the field
replacement of section 5.8, for field `i` of the data block `b`: when `b`'s
count is 1 it stores `x` in place, releasing the field it replaces if the
block's mask says it is a pointer, and returns `b`; otherwise it copies
`b`, header and all, adding a reference to each pointer field it keeps,
stores `x` in the copy, releases `b`, and returns the copy. A field read,
`(.f e)`, is `l0_data_get`. For the field form of 6.5, `(.f r (g ... (.f
r) ...))`, with a field of a counted type, the compiler emits the argument
`(.f r)` as `l0_data_take(r, i)`, where it stands among `g`'s arguments, and
the rest as written: when `r`'s count is 1 it moves field `i` out, leaving 0
in its place, and otherwise adds a reference to it; either way it returns
the field with a reference the caller owns, and allocates nothing. The
outer replacement's `l0_data_with` then stores `g`'s result in `r`,
releasing the 0. While `g` runs, `r` holds a 0 where a field was, which
nothing can read, for the reasons given for `l0_array_take`. Arrays and bytes are allocated
with `l0_host_alloc` and freed with `l0_host_free`, since their sizes are
any number of words, and the free lists are by size and stop at 256 words.
`l0_read_bytes` reads into a buffer that
doubles as it fills and is trimmed to the input's length at the end, and
becomes the bytes block itself, so only `l0_host_resize` ever holds two
copies. `l0_read_some` copies what a stream's handle holds back, at most
`n` bytes, into a new block, filling the handle's buffer with one
`l0_host_read` first when it is empty,
so a piece from a stream is at most the buffer's size, 65,536 bytes,
whatever `n` is; from a handle over a list it is the next `n` elements, or
as many as are left. `l0_write_bytes` copies a range into a stream's
buffer a block at a time, delivering the buffer each time it fills, which
leaves the same bytes in the buffer, in the same order, as calling
`l0_write_to` once per byte would.
Setting `L0_ARRAY_STATS` in the environment makes the runtime report, on
standard error at a normal exit, three lines: how many updates copied, how
many were in place, and how many words the copies moved in all, counting
`array_set`, the row update, and field replacements alike. It is how a
loop can be checked for copying.

Setting `L0_RC_CHECK` in the environment makes the runtime check its own
counting: a freed block is poisoned and never reused, nor its chunk given
back, nor counted by `heap_left`, so any later use of it is a runtime error, and any counted block still live at a normal exit is
reported on standard error. This is how the compiler's counting is tested,
and it costs a program nothing when it is not set.

### 10.4 Two implementation freedoms

A compiler may emit whatever internal names, block labels, and instruction
sequences it likes, and it may generate `alloca` slots for locals and let LLVM's
`mem2reg` build SSA rather than constructing `phi` nodes itself. Neither choice
is observable. An `alloca` outside the entry block runs each time control
reaches it, which is harmless while a function body has no back edges, as
none does when iteration is recursion: each then runs at most once per call.
A compiler that emits a loop within a function must put that function's
allocas in its entry block, or each iteration takes more stack than the last
and section 8's guarantee fails without any diagnostic.

A compiler's output must be a deterministic function of its input. Nothing
derived from memory addresses, hash iteration order, the clock, the environment,
or the filesystem may reach the emitted text. Self-compilation is verified by
comparing output bytes, so any nondeterminism breaks the build for reasons that
have nothing to do with correctness.

