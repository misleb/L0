# 0074: research: the route to a microkernel written in L0

Kind: research
Status: done; regions (0075), a row updated in place through any function
(0076), and a host for processes (0077) are queued, and items 4 to 6 of
the recommendation wait for their programs
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
$ tools/l0check roadmap/0074/progs/uart.l0
roadmap/0074/progs/uart.l0:8:20: error: unknown function load32
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
- 2026-10-09: **finding: an unchanged compiled L0 program runs as a process
  at EL0, in an address space of its own, under a kernel stub, and the
  compiler reaches its fixpoint that way, preempted, beside a process the
  kernel killed for a fault.** Prototype in `roadmap/0074/`: `kernel.ll`
  (1,003 lines, 191 of them assembly) and `kernel.ld`, the stub; `proc.ll`
  and `proc.ld`, a host file for a process; `fault.ll`, a process that is
  not L0; `build.sh` and `run.sh`; `progs/` the programs below. Images link
  in the `l0-virt-link` container, as `--target virt`'s do.
  - **The measure, half of it.** `build/stage2.ll`, built as a process in
    slot 0 with `runtime/l0rt.ll` unchanged and `proc.ll` as its host,
    compiled `build/compiler-source.l0` (209,340 bytes, read by system
    calls) to a result byte-identical to `build/stage3.ll` and
    `bootstrap/stage2.ll`, while the kernel time-sliced it against
    `progs/spin.l0`, which never yields (288 and 289 preemptions), after
    killing `fault.ll` for reading the kernel's image (`esr
    0x9200000d`, a level 1 permission fault, `far 0x40080000`). 8.79 s so;
    5.65 s alone, against 5.01 s for the same compiler on the bare board
    (`tools/l0 boot build/stage2.elf`), so a process costs about 13% under
    emulation, timer interrupts every 10 ms included. 25 system calls; 20
    blocks of 2 MB touched, 40 MB, the first measure of the compiler's
    memory on the board. `tests/virt/runtime_error.l0` and `stack.l0` give
    their messages and status 70 as processes, as on the board. The other
    half, I/O carried by an L0 driver process, needs regions, interrupts,
    and system calls for drivers, below
  - **The line between L0 and the host file holds, per facility.**
    Everything in `kernel.ll` that a hardware format decides is mechanism
    the host file keeps: the vector table; `k_user_run`, which saves the
    caller's x19 to x30 and d8 to d15, loads TTBR0 and 102 words of
    registers, q0 to q31, fpcr, and fpsr included, and erets, and whose
    traps save them back and return; descriptor bits; ASIDs; the GIC;
    the timer's system registers; semihosting. Everything else is policy an
    L0 kernel would hold, and none of it needs raw memory: `k_main`'s loop,
    `pick`, the system call dispatch, whether a fault is a block to map or a
    process to kill, and the report. The descriptor constants had to be
    computed by hand, the PXN and UXN bits, AP, nG, and the attribute
    index, and getting one wrong maps the kernel into a process or makes
    its code writable: the bug class handles keep out of L0. The candidate
    for section 8 stands: no builtin gives L0 a pointer, a region never
    covers the runtime's memory, and only frames from the pool can be
    mapped. One addition: the stub reads and writes a process's buffers by
    address, after `user_range` checks and maps them. In L0 that is
    `space_read` and `space_write` on a space handle, copying to and from
    bytes, so an L0 kernel never holds a process's address as a pointer,
    and the host can turn on PAN and copy with unprivileged loads
  - **The kernel's shape works, and found a limit.** One loop, interrupts
    masked, with `k_user_run(ctx)` returning at the next trap with the
    reason, is the whole kernel. `progs/kloop.l0` is that loop in L0 today,
    with `user_run` simulated by a function that consumes a context and
    returns it updated, over a table of three 102-word contexts, a million
    traps, built natively. Written plainly, `(array_set g t (sim_run
    (array_get g t) k))` copies the context every trap: 48 ns a trap,
    1,000,000 copies, 102,000,000 words (`L0_ARRAY_STATS`). That is what
    section 6.5 says, since its one in-place form is a nested `array_set`
    and `array_get` gives the row a holder of its own. Taking the context
    out first, leaving an empty array in its place, updates in place: 12
    ns, 2 copies, both from `array_new` sharing one row. Decoding each trap
    into a `Trap` data value, as a library over `user_run` would, makes it
    16 ns. So per trap an L0 kernel's loop costs nanoseconds once the table
    updates in place, but the natural way to write it copies, and the way
    that does not is a workaround. That is a language item: a row taken
    from an array updates in place through any function, written the
    natural way, generalizing 0025's nested form, with `kloop.l0`'s
    natural mode as its Why
  - **Regions.** The stub's devices took 8 and 32-bit volatile accesses,
    the PL011's data and flag registers and the GIC's; page tables and
    DMA rings take 64. On one core, volatile accesses to memory the host
    maps as device memory are enough; DMA needs a barrier between writing
    a descriptor and ringing the doorbell, so a barrier builtin belongs
    with regions, and an ordering, not only volatility, is what a kernel
    per core will need of a region's atomic later. Regions come from the
    device tree QEMU puts at 0x40000000, which says which ranges are
    devices: the host opens a region only over one of those or over a
    frame from the pool, and gives -3 otherwise, which is also all a host
    with an operating system gives
  - **Address spaces and frames.** 2 MB blocks at level 2, not global,
    tagged with ASIDs, switch with one write of TTBR0 and no flush; the
    kernel's identity map is the same in every space, EL1 only and never
    executable at EL0. Mapping a heap or stack block the first time it is
    touched kept the compiler to 20 blocks of a 640 MB layout. Three things
    the stub left undone are the host file's, not L0's: freeing frames,
    with `tlbi aside1is` before an ASID is reused; W^X, since a 2 MB block
    holds both a process's code and its data, which needs level 3 tables
    of 4 KB pages; and making the kernel's own image read-only and
    execute-only, which `host-virt.ll`'s 1 GB blocks cannot express either.
    `virt.ld` keeps its layout, with a pool of frames beside the heap
  - **The timer and interrupts.** The board's interrupt controller is a
    GICv2 (`arm,cortex-a15-gic`), its distributor at 0x08000000 and CPU
    interface at 0x08010000; GICv3 is `gic-version=3`. The virtual timer
    is PPI 27, the PL011 SPI 1 (INTID 33). The stub drives the GIC with
    six 32-bit accesses, which an L0 kernel can make through regions; the
    timer's deadline is a system register, `cntv_tval_el0`, so it is a
    builtin. A slice starts only when the kernel moves to a process: one
    re-armed after each system call never ends while the process keeps
    calling. Preempting only at the end of a slice sufficed; nothing here
    needed to ask whether an interrupt is pending, nor to wait for one,
    since a process was always runnable. Waiting (`wfi`) is needed once a
    process can block on IPC
  - **A host for processes.** `proc.ll` is `host-virt.ll` without its boot
    code, serial port, and semihosting, and with three system calls: read,
    write, and exit. Nothing else crossed to the kernel. The allocator runs
    in the process over its own heap; the clock is read in the process,
    since the kernel sets `cntkctl_el1` so EL0 may read the counter; files,
    arguments, and settings are section 9.2's absences. So the spec fixes a
    system call only for what leaves a process: the streams, opening,
    closing, renaming, removing, and exit, and arguments and settings if a
    kernel is to give them. A process's layout is fixed (`proc.ld`): image
    at 0xC0000000, heap, stack. It builds with today's toolchain: clang
    links `l0rt.bc` and the host's bitcode as `--target virt` does, and
    `ld.lld` places it at its virtual addresses, loaded at a physical one
    (`--defsym=__load`). QEMU's loader puts each image at its ELF's
    physical address, which is how three reached the board; a real kernel
    reads images from its standard input, which the board already loads
  - **System calls for drivers.** Not prototyped: the stub's own calls are
    the host's. The numbers a host file uses are fixed by the spec, and a
    kernel's own start after them, which is all `supervisor_call` needs to
    keep the two apart
  - **DMA.** The board's SMMUv3 (`-machine virt,iommu=smmuv3`, at
    0x09050000) translates only the PCIe bridge: its node has an
    `iommu-map`, the `virtio_mmio` nodes have no `iommus`. So the first
    drivers, the PL011 and virtio-mmio, cannot be contained, and a
    contained one is a virtio-pci device behind the SMMU, which needs PCIe
    enumeration through ECAM, at 0x4010000000 unless `highmem=off`, beyond
    the 32-bit physical addresses `host-virt.ll`'s TCR gives. That waits
    for a driver that needs it
  - **Where the code lives, and the measure as a test.** As planned: the
    kernel in a project of its own, each facility earned here by a program
    in `tests/virt`. `kernel.ll`'s stub can serve as the kernel the process
    host is tested against until an L0 kernel replaces it, as
    `tests/backend` holds hand-written IR
  - **What stays out.** `k_cur_ctx` and `k_saved_sp` are single globals,
    the one place the stub assumes one core: in a host file they belong per
    core, behind `tpidr_el1`. Since a context carries its own TTBR0, moving
    a process between cores needs no more in it. Accounting for the
    kernel's heap, threads within a process, and migration stay out
  - **Recommendation**, in order; queueing them is the user's call:
    1. language: regions, with sized volatile reads and writes, a barrier,
       and -3 where the host has none. `progs/uart.l0` is its Why; the
       PL011 driver in `tests/virt` is what it earns
    2. language: a row taken from an array updates in place through any
       function, written the natural way. `progs/kloop.l0`'s natural mode
       is its Why. Independent of the rest, and the kernel's table needs it
    3. language: a host for processes: section 9.2 and 10.3 say what a
       process of a kernel is and fix its system calls, `proc.ll` becomes
       `runtime/host-proc.ll`, `l0 build` gets a target for it, and
       `tests/virt` runs programs as processes under `kernel.ll`'s stub as
       a hand-written harness. The prototype is its Why
    4. language: a timer deadline and waiting for an interrupt, earned by
       the serial driver receiving by interrupt through the GIC's regions
    5. language: user mode: `user_run`, space and frame handles,
       `space_map`, `space_unmap`, `space_read`, `space_write`, and a
       library type for traps; earned by `kernel.ll`'s loop written in L0,
       which then replaces the stub as the harness
    6. language: `supervisor_call` for drivers and servers, numbered after
       the host's, and a library type over it; earned by a driver serving
       another process
    7. program: the kernel, in its own project, standing, reporting limits
    8. tooling: the measure as a test in `tools/test.sh --virt`, the
       compiler as a process with its I/O through an L0 driver
    Items 4 to 6 have no code in their Why yet; each earlier item's program
    is meant to produce it. Next: the user decides what to queue.
- 2026-10-09: the user queued items 1 to 3 as 0075, 0076, and 0077. Items
  4 to 6, the timer and interrupts, user mode, and `supervisor_call`, are
  opened when an earlier item's program gives them a Why. Done. The
  prototype in `roadmap/0074/` stays until 0077 moves it.
- 2026-10-09: **finding: what a second board costs, and where its details
  live.** Asked by the user, with the Raspberry Pi 3B (`-M raspi3b` in
  this QEMU) as the board; nothing built, and the Pi's details are from its
  documentation, not tried here.
  - **In this repository, not the kernel's.** A board's details are its
    host file, its linker script, and its target in `tools/l0`, never the
    compiler or the emitted IR (section 9.2). The host file stays here,
    since it is what keeps section 8's guarantee, and a kernel project
    that brought its own could break it unseen. So each board is a change
    to the toolchain, not to the kernel
  - **The Pi 3B's share.** About 150 lines of `host-virt.ll` are the
    board's; the allocator, the `mem` functions, the clock, and the trap
    report are not. Its host would leave EL2 (or EL3 under QEMU) for EL1,
    park cores 1 to 3 by `MPIDR`, and build a level 2 map, since its RAM
    and its peripherals at 0x3F000000 share the first gigabyte. Its PL011
    is at 0x3F201000, and it has its own device table and a layout at
    0x80000 in about 1 GB. Under QEMU, standard input by the loader and
    standard error and exit by semihosting carry over; on the board itself
    semihosting is gone, and both need a channel the hardware has, 0073's
    question again
  - **Decided by the user:**
    1. 0077 widens: a process's host names no board, and the arguments and
       `l0_host_region` are system calls, so that a kernel starts a driver
       with its device's base and interrupt as arguments and maps the
       device for it, and one driver serves every board with that device.
       The Pi 3B has a PL011 too
    2. item 4 puts the interrupt controller in the host file, behind
       builtins for enabling an interrupt by number, waiting for one and
       getting its number, and acknowledging it, and takes the GIC's
       distributor and CPU interface out of `host-virt.ll`'s regions, so
       L0 cannot reprogram it behind the host; whether the GICv2m frame
       goes with them is item 4's to settle. This reverses this item's
       finding that the stub drives the GIC through accesses an L0 kernel
       can make through regions, and the 0075 changelog's line that the
       kernel's interrupt controller starts as a driver does. Why: the
       controller is on every trap's path and its format is the
       hardware's, the test that put the vectors in the host file; and a
       kernel holding a GIC driver would not run on the Pi 3B, which has
       none (its interrupts go through the BCM2836 local controller). Item
       4's program is unchanged, the serial driver receiving by interrupt
    3. the device tree waits. With one board the fixed table is right, as
       the 0075 changelog argues. Taking regions from it is two parts: the
       host checks a range against the tree's device nodes, and a builtin
       gives the kernel the tree's bytes. It is opened by a second board,
       or by a kernel that cannot hard-code a driver's interrupt number
  - With all three, a kernel project knows a board only through its
    drivers and the list of those it starts, and its kernel is one image
    on every board
- 2026-10-09: **when the kernel project starts, decided by the user.**
  Item 7 opens right after item 5, not after item 6: before `user_run` an
  L0 kernel could return to no process, and could only ship `kloop.l0`'s
  simulated one, the workaround item 7 must not write; and item 6's Why, a
  driver serving another process, is what a standing kernel produces. The
  project starts from item 5's kernel loop in `tests/virt`. Until then each
  facility is earned here, and a project made by `l0 init` would follow an
  installed toolchain that is still gaining builtins. Two gaps stand in its
  way, neither queued, each to be settled before item 7 opens or recorded
  as its first limits:
  - `l0 test` refuses `--target virt` ("runs on this host only; a test is
    named by an argument, and the virt board gives none"), so a kernel
    project could not run its own tests on the board. Under a kernel the
    arguments are 0077's system calls, so a test could run as a process,
    but nothing in the driver does that
  - nothing bundles several images for the board. The prototype placed
    each at its ELF's physical address with QEMU's loader; a kernel is to
    read its processes from its standard input, which the board loads, and
    no `tools/l0` command writes that input
