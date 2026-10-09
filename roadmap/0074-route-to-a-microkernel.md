# 0074: research: the route to a microkernel written in L0

Kind: research
Status: active
Needs: nothing

## Why

The README's "A microkernel" goal, recorded in the changelog as "A new goal:
a microkernel written in L0": a kernel written in L0 runs drivers and
programs as L0 processes, each in an address space of its own. The measure
is the compiler compiling itself to the same bytes as a process on that
kernel, its standard input and output carried over IPC by a serial driver
that is an L0 process too, and a driver that fails stopped without stopping
the kernel.

The first thing a driver needs cannot be written. This waits while the
PL011's transmit FIFO is full, flag register bit 5, and then stores the
byte to its data register:

```
(def uart_base () int 150994944)      ; 0x09000000

(def put ((b int)) int
  (if (eq (bit_and (load32 (add (uart_base) 24)) 32) 32)
      (put b)
      (store32 (uart_base) b)))
```

```
$ tools/l0check tmp/0074/uart.l0
tmp/0074/uart.l0:8:20: error: unknown function load32
```

A kernel needs more than that: to run code in user mode and get control
back when it traps, address spaces, a timer, and interrupts. None of them
is a single language item yet, and none has its smallest program.

## The question

What is the smallest sequence of bootstrapped changes from here to the
measure? Settle at least:

- **The line between L0 and the host file.** The kernel's L0 holds policy:
  which thread runs, who may map what, where IPC goes, what a capability
  allows, how an ELF image is loaded. The host file holds what the
  hardware's formats decide: the vector table, saving and restoring
  registers, `eret`, the encoding of page-table descriptors, TLB and cache
  maintenance. Confirm or move that line, per facility, and say what
  section 8's guarantee becomes. The candidate: a region read returns an
  integer, never a pointer, no region covers the runtime's own memory, and
  only frames from a pool the host hands over can be mapped, so a kernel
  bug cannot map its own heap into a process. Weigh it against raw loads
  and stores, which put page tables in L0 and give the checker nothing.
- **The kernel's shape.** One loop, run with interrupts masked, as seL4's
  is: pick a thread, return to it with `user_run`, handle the trap it comes
  back with, carry the kernel's state to the next tail call. Whether a
  thread's context as an `(array int)` of registers, updated in place, and
  a trap as a library data type over codes, as `IoOpened` wraps an open's,
  serve; and what one trap costs in allocation and reference counting.
- **Regions.** The form: a handle over a range of physical or device
  memory, reads and writes of 8, 16, 32, and 64 bits, out of range a
  runtime error as `array_get`'s is, and a barrier. Whether accesses are
  volatile only, or carry a memory ordering, which a kernel per core would
  need later. Where a region comes from: the device tree, a fixed table in
  the host file, or what the kernel maps into a driver's space. What a host
  with an operating system gives, as section 9.2 does for files.
- **Address spaces and frames.** Handles for both, `space_map` and
  `space_unmap` with permissions, ASIDs, and the TLB flushed inside them.
  How the host splits memory between the runtime's heap and the pool of
  frames, in `runtime/virt.ld`. Whether the kernel's own code becomes
  read-only and execute-only, and user memory unreachable from the kernel
  except by a deliberate copy.
- **The timer and interrupts.** Which interrupt controller the board gives
  (GICv2 by default, GICv3 with `gic-version=3`), and whether L0 drives it
  through regions. A deadline for the generic timer, which is a system
  register and so a builtin, and waiting for an interrupt (`wfi`) when no
  thread can run. Whether processes are preempted only at the end of a
  slice, and whether the kernel needs to ask if an interrupt is pending, to
  split a long operation, as seL4's preemption points do. How long a pass
  can take, given that a release in section 10.3 frees all a value kept
  alive before it returns.
- **A host for processes.** One system call for each `l0_host_*` function
  of section 10.3, fixed by the spec, so that one host file in this
  repository serves every L0 kernel, and the kernel decides how to answer
  them, such as by forwarding writes to a console driver. Where a process's
  heap and stack come from. How a process is built, `l0 build --target`
  what, and how several reach the board: the kernel's standard input, which
  the board already loads, can carry them.
- **System calls for drivers and servers.** One `supervisor_call` builtin
  from words to words, with the ABI the kernel's own and a library giving
  it types, against IPC builtins the spec defines. Whether a driver that
  waits for its interrupt needs anything else.
- **DMA.** Whether virtio devices on the board can be put behind its IOMMU
  (`-machine virt,iommu=smmuv3`), so that a driver's DMA reaches only what
  it was given, and what a region for DMA needs: the physical address of
  its frames, and cache maintenance.
- **Where the code lives, and the measure as a test.** The kernel is a
  program in a project of its own, made by `l0 init`, using the installed
  toolchain, and reporting limits rather than routing round them; each
  facility is earned here by a smaller program in `tests/virt`, such as the
  serial driver above. Say how the measure becomes a test in `tools/test.sh
  --virt`: vendoring a pinned kernel, or bringing it in once it is stable.
- **What stays out.** More than one core, migrating processes between
  cores, accounting for the kernel's own heap, and threads within a
  process. Say what each would need, and which facilities above must not
  assume one core, so that a kernel per core, sharing no L0 value, is an
  addition later rather than a rewrite.

## The hypothesis to test

The order the research is expected to confirm or reshape, each language
item one bootstrapped change, none of them used by the compiler, so none
needs the two-step rule:

1. language: regions, with sized reads and writes and a barrier; the
   serial driver above, in `tests/virt`
2. language: a timer deadline and waiting for an interrupt; the serial
   driver receiving by interrupt
3. language: user mode, address spaces, frames, `user_run`, and a library
   type for traps; a kernel running two processes
4. language: a host for processes an L0 kernel runs, over system calls,
   and `l0 build` for it; an unchanged echo program run as a process
5. language: `supervisor_call` for drivers and servers, and a library type
   over it; a driver serving another process
6. program: the kernel, in its own project, standing, reporting limits
7. tooling: the measure as a test in `tools/test.sh --virt`

## Done when

- the Log has a finding answering each question above
- a prototype in `roadmap/0074/`: a hand-written kernel stub in IR, beside
  `runtime/host-virt.ll`, that runs a program compiled by today's compiler,
  unchanged, at EL0 in an address space of its own, with its standard
  input and output through system calls into the stub, and that reports a
  fault in the program and keeps running. This tests the vectors, the
  context switch, and the page tables with no language change, as 0068's
  prototype tested the board with none
- a recommendation naming the first item and those after it, in order,
  through the measure, each language item with the smallest program that
  cannot be written without it

## Log

- 2026-10-09: opened with the goal, at the user's request, after the
  bare-metal goal's items (0069 to 0072) were done. The serial driver above
  is the first limit, checked here. Next: the line between L0 and the host
  file, and the prototype.
