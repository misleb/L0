# A program run as a process

Part of the specification of L0, with [L0.md](../L0.md) and
[runtime.md](../runtime.md): the host of section 10.3 for a program a
kernel runs as a process, its system calls, its image, and its layout.
Normative.

**A process's host.** A process's host runs a program as a process at user
level of a machine, at EL0 of an aarch64 one or in U-mode of a riscv64 one,
and what a kernel must give it for that is fixed here, so that any kernel
that gives it runs every L0 program unchanged; `l0 build --target proc
--arch ARCH` builds for one. A process's virtual memory, as `proc.ld` lays
it out on both:

| Address | What |
| --- | --- |
| 0xC0000000 | the image's segments, code, rodata, and data with its bss, ending below 0xD0000000 |
| the image's end | the heap, from the first page at or after it, to 0xD8000000 |
| 0xD8000000 | the stack, growing down from 0xE8000000 |
| 0xE8000000 | up to 0x100000000: the kernel's, where it maps the process's regions and what it shares with it |
| 0x2000000000 | up to 0x4000000000, the high user range on the boards' hosts: the kernel's too, 128 GB |

The image is a static ELF executable, which is what `l0 build --target
proc` writes, and a kernel loads it knowing only this:

- `ELFCLASS64`, little endian, `ET_EXEC`, and `e_machine` the CPU's,
  `EM_AARCH64` (183) or `EM_RISCV` (243). It has no `PT_INTERP`,
  `PT_DYNAMIC`, or `PT_TLS`, and nothing in it is relocated.
- `e_entry` is the entry point, 0xC0000000 as `proc.ld` lays it out.
- At most three `PT_LOAD` segments, in address order and not overlapping:
  the code, `PF_R` and `PF_X`; the rodata, `PF_R`; and the data, `PF_R`
  and `PF_W`, whose `p_memsz` past its `p_filesz` is the bss. None is
  both writable and executable. Each has `p_offset` and `p_vaddr`
  multiples of 4096 and `p_align` 4096, so a kernel copies whole pages,
  and all lie from 0xC0000000 to below 0xD0000000, which `l0 build`
  refuses an image to pass, so the heap has at least 128 MB. A segment
  that would be empty may be left out or have a `p_memsz` of 0.
- The ELF header and the program headers lie in no `PT_LOAD`. Other
  program headers, the section table, and the symbols may be present, and
  a kernel ignores them; the symbols are kept so a fault's address can be
  named.

The image's end is the highest `p_vaddr` plus `p_memsz` of its `PT_LOAD`s,
and the heap starts at the first multiple of 4096 at or after it, which is
`__heap_start` in `proc.ld`: so a kernel learns where the heap starts from
the headers, and nothing more is passed to the process. The kernel maps
each segment's `p_filesz` bytes from `p_offset` at `p_vaddr`, the rest of
its pages to `p_memsz` zero, and the heap and stack zero, though it may
map a page of the heap or stack only when it is first touched. It maps
each segment with at least its flags' permissions and the heap and stack
readable and writable, and may give more, so a kernel that maps every
page readable, writable, and executable runs every program; a program
writes no page of its code or rodata, and executes none of its data,
heap, or stack. A kernel may refuse an image for another CPU. It starts
the process at `e_entry` with `sp` at 0xE8000000 and floating point
enabled: on aarch64
SIMD too, and the virtual counter readable at EL0
(`CNTKCTL_EL1.EL0VCTEN`); on riscv64, `sstatus.FS` not off.

A **system call** is, on aarch64, `svc #0`, with its number in `x8`, its
arguments in `x0` to `x3`, and its result in `x0`, and on riscv64,
`ecall`, with its number in `a7`, its arguments in `a0` to `a3`, and its
result in `a0`, the kernel resuming the process after the `ecall`; the
kernel keeps every other register.
A buffer or path is an address in the process and a count of bytes; the
kernel checks that the process may read or write all of it, and gives -5
if it may not. A path is passed without the NUL that `l0_host_open` and the
others are given. The numbers below 256 are this table's, and a kernel's
own calls are numbered from 256:

| Number | Call | Arguments | Result |
| --- | --- | --- | --- |
| 1 | read | stream, buf, n | as `l0_host_read` |
| 2 | write | stream, buf, n | as `l0_host_write` |
| 3 | exit | status | none: the process ends |
| 4 | open | path, its length, mode | as `l0_host_open` |
| 5 | close | stream | as `l0_host_close` |
| 6 | rename | from, its length, to, its length | as `l0_host_rename` |
| 7 | remove | path, its length | as `l0_host_remove` |
| 8 | arg_count | | as `l0_host_arg_count` |
| 9 | arg | i, buf, n | the length of argument `i`, having copied at most `n` of its bytes to `buf`, or -5 if there is no argument `i` |
| 10 | region | base, len | the address in the process at which the `len` bytes of device memory at `base` are mapped, as `l0_host_region`'s are, or -3 if the kernel gives no region there, or -5 if it can map no more |
| 11 | clock | | as `l0_host_clock_ns` |
| 12 | release | base, len | 0; the whole pages of the heap from `base` to `base + len` hold nothing the process needs, below |
| 13 | unregion | addr, len | 0; the region call that gave `addr` for these `len` bytes is undone, below |

A process's host asks for every argument once, before the program starts,
and keeps each NUL-terminated for `l0_host_arg`; if the heap cannot hold
them, the process stops with the runtime error `heap exhausted`. What stays in the process is what needs no kernel:
the allocator, over the heap above; the barrier, `dsb sy` or `fence iorw,
iorw`; settings, which are section 9.2's absence of an environment; and
on aarch64 the clock, from the virtual counter, at `cntfrq_el0` counts a
second. A riscv64 process can read the time but not its rate, which is
the board's, so it asks its kernel, by call 11, which every kernel
answers. Exit is the kernel's to report, as section 9.2 leaves what
receives the status to the host.

Call 12, release, tells the kernel that the `len` bytes from `base`, a
multiple of 4096 and a whole number of pages of the heap, hold nothing
the process needs. The kernel may unmap any of those pages and free their
frames, and a later touch of one then gets a zeroed page, as a first
touch does. It may also do nothing: the process ignores the result, so a
kernel that answers 12 as a call it does not know runs every program. No
page outside the heap is named, and what a kernel does with one is its
own. The process makes the call from `freestanding.ll`'s `l0_host_free`,
once a freed block is merged with its free neighbours, naming the whole
pages of the merged block that hold none of the allocator's own words, a
free block's first 32 bytes and its last 8, and lie at least in part in
the block freed: so a page is named once, as it comes free, and not again
for each block that later joins it. That is every array and bytes value
and every chunk the runtime gives back past the 4 it keeps; those 4, and
the blocks on its free lists, stay touched, since they are what it cuts
from next. A board's host has no kernel, and names nothing.

Call 13, unregion, tells the kernel that the process will not touch the
`len` bytes at `addr` again, where `addr` is what call 10 gave for a
region over `len` bytes: `l0_host_region_close` makes it, so for a region
`region_close` closed, or one the runtime had no room for. The kernel may
unmap the pages it mapped for that call and map them again for a later
one, and a later touch of one then traps as at a page never mapped. It
may also do nothing: the process ignores the result, so a kernel that
answers 13 as a call it does not know runs every program, and can then
map only as many regions over a process's life as call 10 has room for.
`l0rt.ll`'s table, not the kernel, decides whether a region is open, so
a kernel is never told of one region twice, and what it does with an
`addr` call 10 never gave is its own.

A kernel's own calls, numbered from 256, are the program's (6.15):
`l0_host_supervisor(n, a, b, c)` makes call `n` with `a`, `b`, and `c` as
its first three arguments, the fourth 0, and returns its result. `l0rt.ll` checks `n` and the bytes
first, and for `supervisor_send` and `supervisor_receive` passes in `b`
the address of the bytes' first byte in the process and in `c` their
count. `host-libc.ll` and a board's host have no kernel beneath, and
return -3.
