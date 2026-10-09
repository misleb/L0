# 0077: a host for programs run as processes by a kernel

Kind: language
Status: done, changelog "A host for programs run as processes by a kernel"
Needs: 0074

## Why

[0074](0074-route-to-a-microkernel.md)'s prototype ran the compiler as a
process at EL0, in an address space of its own, under a kernel stub, to
the seed's bytes, with `runtime/l0rt.ll` and the program unchanged. It did
so through prototype scripts and a host file that only `roadmap/0074/`
has. The driver has no way to ask for it:

```
$ tools/l0 build --target proc roadmap/0074/progs/echo.l0 -o tmp/echo-proc.elf
l0: unknown target proc; the targets are host and virt
```

and section 9.2 names two hosts, an operating system and a machine with
none, not a process of a kernel.

## Done when

- the checklist in the `l0-bootstrap` skill
- section 9.2 says what a host that is a process of a kernel gives: what
  section 6 and 9 rely on, reached through system calls, and section 9.2's
  absences otherwise. Such a host names no board: a process's layout is
  virtual and its clock is the architecture's, so one process image runs
  under any aarch64 kernel. Section 10.3 fixes the system calls a
  process's host file makes, one for each `l0_host_*` function that leaves
  the process: the streams, opening, closing, renaming, removing, and exit,
  as 0074 found, and also the arguments and `l0_host_region`, so that a
  kernel can tell a driver where its device is and map that device into
  the driver's space, and the driver names no board either. They are
  numbered so that a kernel's own calls come after them; the allocator,
  the clock, and the barrier stay in the process, and settings are section
  9.2's absence. The changelog says why
- `runtime/host-proc.ll`, from `roadmap/0074/proc.ll`, and a layout for a
  process beside `runtime/virt.ld`
- `tools/l0 build --target proc`, which installs its runtime as `--target
  virt` does
- `roadmap/0074/kernel.ll` moves into `tests/virt` as a hand-written
  harness, as `tests/backend` holds hand-written IR, and `tools/test.sh
  --virt` runs programs as processes under it against the board's
  expectations, the fault and preemption cases of 0074 included. The stub
  gives a process arguments and answers the region system call by mapping
  the device into the process's space, so `tests/virt/device.l0` and
  `region_ranges.l0`, the code that earns that call, pass as processes
  too. The stub stays the virt board's, since it drives the GIC; it is a
  harness, not the kernel
- `tools/bootstrap.sh --virt` checks the fixpoint as a process too
- `roadmap/0074/` is deleted once its prototype has moved, keeping only
  what 0076 and 0075 still cite, or pointing at the commit that held it

## Log

- 2026-10-09: opened by 0074's recommendation, item 3, and queued at the
  user's request.
- 2026-10-09: widened at the user's request, after asking what a second
  board would cost (0074's Log): a process's host names no board, and the
  arguments and `l0_host_region` become system calls beside 0074's six.
  Both are settled here because this item fixes the numbers in section
  10.3, and adding a call later would renumber the kernel's own. Next:
  start it.
- 2026-10-09: done. Sections 9.2 and 10.3 say what a process of a kernel
  is and fix its layout and ten system calls, numbered 1 to 10 with the
  host keeping everything below 256. `runtime/host-proc.ll` and
  `runtime/proc.ld` are the process's host; the allocator and the `mem`
  functions moved from `host-virt.ll`, unchanged, into
  `runtime/freestanding.ll`, which both link. `l0 build --target proc`
  and `l0 link --target proc` build an image; `l0 run` and `l0 test`
  refuse the target, since no kernel comes with the toolchain.
  - **Found on the way:** `freestanding.ll` needs `strlen` too. With
    arguments, `l0rt.ll`'s loop that measures one is live, and LLVM made
    it a `strlen` call that nothing defined; on the board the loop was dead
    code. Section 10.3 now lists it beside `bcmp`
  - **The harness:** 0074's `kernel.ll` is `tests/virt/proc/harness/`,
    with `fault.ll`, `spin.l0`, and `boot.sh`, which links the kernel and
    loads each process's raw bytes at its slot with QEMU's loader. It now
    answers all ten calls, gives slot 0 the arguments `boot.sh` loads,
    maps devices by 4 KB pages into a window at 0xE8000000, writes nothing
    but its kill lines, and exits 99 when slot 0 is killed. The
    prototype's buffer check let an address near 2^64 wrap past its top;
    it is bounded first now
  - **Tests:** `tools/test.sh --virt` runs the ten `tests/virt` programs
    as processes against the board's expectations, `device` and
    `region_ranges` among them, and `tests/virt/proc`: `args`,
    `preempted` (beside `spin`, which runs first), and `fault_beside`
    (beside `fault.ll`, killed with `esr 0x9200000d`). 86 passed, from 73,
    in 120 s, from 97. `tools/bootstrap.sh --virt` reaches the fixpoint as
    a process too, in 6 s, as on the board
  - `roadmap/0074/` is deleted; it is in git history at commit dfdd1fe
- 2026-10-09: what is open: 0074's items 4 to 6, the timer and interrupts,
  user mode, and system calls for drivers, each waiting for its program,
  and the two gaps 0074's Log names before the kernel project starts.
