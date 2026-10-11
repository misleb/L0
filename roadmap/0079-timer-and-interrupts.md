# 0079: a timer deadline, interrupts, and waiting for one

Kind: language
Status: done, changelog "Interrupts: a timer deadline, and taking, waiting
for, and ending one"; passed on Linux arm64
Needs: 0078

## Why

[0074](0074-route-to-a-microkernel.md)'s item 4. `tests/virt/user/kernel.l0`
now runs several processes, and runs `tests/virt/proc/fault_beside.l0`
beside `fault.ll` to its expectations. But `tests/virt/proc/preempted.l0`
beside `spin.l0`, which runs first and never traps, never ends:

```
$ perl -e 'alarm 30; exec @ARGV' tests/virt/user/run.sh kernel.elf w preempted.elf spin.elf
exit 142, after 30.29 s
```

Under the IR harness, whose timer preempts `spin`, the same pair takes
0.19 s. Nothing in L0 can take the processor back from a thread. This is
the kernel's loop given a slice (`roadmap/0079/why.l0`):

```
(def slice ((s int) (c (array int))) (array int)
  (let t (timer_at (add (clock_ns) 10000000))
    (user_run s c)))
```

```
roadmap/0079/why.l0:6:10: error: unknown function timer_at
```

## The design

0074's Log, as the user decided there and again here: the host file owns
the interrupt controller, behind builtins for enabling an interrupt by
number, waiting for one and getting its number, and acknowledging it, and
the GIC leaves `host-virt.ll`'s regions, so L0 cannot reprogram it behind
the host. The user chose that whole set over the timer alone, though only
the timer has a program yet.

- `(timer_at t)`: the timer's interrupt is pending from when `(clock_ns)`
  reaches `t`, until a new deadline or a negative `t` disarms it
- `(interrupt_enable n)`: interrupt `n` may reach the kernel; 0 is the
  timer's on every host, and a device's are the machine's numbers
- `(interrupt_wait)`: waits until an enabled interrupt is pending, takes
  it, and returns its number
- `(interrupt_done n)`: ends interrupt `n`, taken by `interrupt_wait` or
  by a thread's `user_run`, so it can be taken again
- an interrupt while a thread runs ends `user_run` taken, its number in
  the context; the library's `(TrapInterrupt n)` carries it

## Done when

- the checklist in the `l0-bootstrap` skill, and "Adding a builtin" there
- section 6.14 says what each builtin does, with its runtime error;
  section 8, 9.2, and 10.3 as for 0078; the virt board's interrupt
  numbers in 10.3, and its region table without the GIC. The changelog
  says why
- `host-virt.ll` drives the GIC: initialised at boot, interrupts enabled
  by number, taken in `user_run`'s trap path and by `interrupt_wait`, and
  ended by `interrupt_done`; the virtual timer's deadline. `host-libc.ll`
  and `host-proc.ll` give none
- `tests/virt/user/kernel.l0` runs each process for a slice of the timer,
  and `tools/test.sh --virt` runs `tests/virt/proc`'s `preempted` and
  `fault_beside` under it
- tests on the board of each builtin, the timer's interrupt and a device's
  (the PL011's), and the error; of their absence on this host; and
  `device.l0` and `region_ranges.l0` moved off the GIC

## Log

- 2026-10-09: opened by 0078, at the user's choice to take user mode
  first.
- 2026-10-10: made ready. `kernel.l0` now runs several processes, from a
  table of them in an `(array Proc)` that 0076's form updates in place,
  and `preempted.l0` beside `spin.l0` under it is the Why above. The user
  chose the whole set of interrupt builtins, and removing the GIC from the
  regions though `device.l0` then loses its only device that reads back
  writes of 16, 32, and 64 bits (the PL061 keeps one byte). Next: the
  spec.
- 2026-10-10: implemented. Section 6.14, four builtins and `interrupt not
  taken`, 9.2's absence, 10.3's calls, host functions, the board's
  interrupt numbers, and its regions without the GIC; the changelog says
  why. The checker, emitter, `l0rt.ll`, all three host files, and
  `lib/io.l0`'s `(TrapInterrupt n)`. The seed is refreshed.
  - **The host's GIC:** initialised at boot, with EOImode 1, so taking an
    interrupt drops the running priority at once and `interrupt_done`
    deactivates it: without that, one interrupt taken would hold back
    every other, all being at priority 0. A spurious one sends a thread
    straight back. The timer's deadline rounds up, so it fires no earlier
    than `clock_ns` reads it
  - **Interrupt 0 is the timer's**, the GIC's 27; devices keep their GIC
    IDs, the PL011's 33, confirmed by `tests/virt/interrupts`
  - **The kernel in L0** slices with the timer: `preempted` beside `spin`
    runs in 0.4 s, where it ran until killed; `fault_beside` too; the
    compiler, preempted every 10 ms, reaches the fixpoint in 7 s
  - **Tests:** `tests/virt/interrupts` on the board, the timer's and the
    PL011's interrupt and the error; `tests/io/interrupt_absent` here;
    `device` and `region_ranges` off the GIC, the latter now refused it;
    four checker cases
- 2026-10-10: suites green: 65, 141, and `--virt` 108, from 105, in 151
  s; Linux arm64 65 and 141. Done. What 0074 has left: system calls for
  drivers and servers (item 6), earned by a driver serving another
  process, and the gaps its Log names before the kernel's own project.
