# 0078: user mode: address spaces, frames, and running a thread until it traps

Kind: language
Status: done, changelog "User mode: address spaces, frames, and running a
thread until it traps"; passed on Linux arm64
Needs: 0077

## Why

[0074](0074-route-to-a-microkernel.md)'s item 5. The kernel that runs
processes in this repository is `tests/virt/proc/harness/kernel.ll`,
hand-written IR, and its loop cannot be written in L0. This is that loop,
`k_main`, cut to its shape (`roadmap/0078/why.l0`):

```
(def step ((s int) (c (array int))) int
  (let r (user_run s c)                       ; back at the thread's next trap
    (if (eq (array_get r 35) 1)               ; an interrupt: run it again
        (step s r)
        (array_get r 8))))                    ; else the system call's number

(def main () int
  (let s (space_new)
    (let f (frame_new)
      (let m (space_map s 3221225472 f 1)     ; 0xC0000000, readable and writable
        (step s (array_new 104 0))))))
```

```
$ tools/l0check roadmap/0078/why.l0
roadmap/0078/why.l0:5:10: error: unknown function user_run
roadmap/0078/why.l0:11:10: error: unknown function space_new
```

Taken before the timer and interrupts (0074's item 4) at the user's
choice: one program alone on the board can poll a device, so nothing yet
fails without interrupts, while this loop fails at its first line. Once
an L0 kernel runs processes, `tests/virt/proc/preempted.l0` is the
program that fails without a timer, and earns item 4 (0079).

## The design

0074's line between L0 and the host file: the host keeps what the
hardware's formats decide, the page-table descriptors, ASIDs, the TLB,
saving and restoring registers, and `eret`; L0 holds handles and policy.
No builtin gives L0 a pointer, and only frames from the host's pool are
ever mapped into a space, so a kernel bug cannot map its own heap into a
process.

- `(space_new)` an address space, `(frame_new)` a zeroed 4 KB page from
  the pool; -5 when none is left, -3 on a host with no user mode
- `(space_map s va f perm)`: a frame at a user page, readable, and
  writable and executable as `perm`'s bits say
- `(space_map_device s va base len)`: the pages of a device range, with
  the host's own check of what is a device, so a kernel can answer a
  process's region call without knowing the board
- `(space_read s va n)` and `(space_write s va b i j)`: copies out of and
  into a space, as bytes, so the kernel never holds a process's address
- `(user_run s c)`: runs the thread whose registers the `(array int)` `c`
  holds until it traps, and returns them updated with the trap's kind,
  syndrome, and address; 0076 makes the natural loop update it in place
- the library's `Trap` decodes a context's trap, and `user_context` makes
  one

## Done when

- the checklist in the `l0-bootstrap` skill, and the list under "Adding a
  builtin" there
- section 6.13 says what each builtin does and the runtime errors of
  misusing one; section 8's table has them; section 9.2 says which hosts
  have no user mode; section 10.3 has the runtime calls, the host
  interface, the board's user range, frame pool, and the aarch64 context
  layout. The changelog says why
- `runtime/host-virt.ll` gives user mode: the pool, spaces with ASIDs,
  4 KB pages, the copies, and `user_run`'s entry and trap path;
  `host-libc.ll` and `host-proc.ll` give none
- `lib/io.l0` has `Trap`, `trap_of`, and `user_context`
- `tests/virt/user/kernel.l0`, a kernel in L0 that loads one process image
  from its standard input and answers spec 10.3's system calls, runs the
  `tests/virt` programs as processes against the board's expectations, and
  reports a process that faults, under `tools/test.sh --virt`; and
  `tools/bootstrap.sh --virt` reaches the fixpoint with the compiler as a
  process of it
- tests of each builtin's results and errors on the board, and of their
  absence on this host

## Log

- 2026-10-09: opened at the user's request, before 0074's item 4, which
  is queued behind it as 0079. Next: the spec.
- 2026-10-09: implemented. Section 6.13, seven builtins, seven runtime
  errors, 9.2's absence, and 10.3's calls, host functions, user range,
  pool, and 104-word context; the changelog's entry says why. The
  checker, the emitter, `l0rt.ll`, all three host files, `virt.ld`
  (heap to 0x98000000, the pool after it), and `lib/io.l0`'s `Trap`,
  `trap_of`, and `user_context`. The seed is refreshed.
  - **Found on the way:** the order of checks needed the host to check
    `perm` too, and an empty copy first for `space_read` and
    `space_write`, so a bad space is reported before a bad count;
    `space_map_device`'s -3 comes before its page errors, so a kernel may
    pass on a process's request unbounded; and mapping can run out of
    pages for tables, so `space_map` gives -5. Frames come from the
    bottom of the pool and tables from the top, so frames are numbered
    0, 1, 2 whatever tables exist
  - **The kernel in L0:** `tests/virt/user/kernel.l0`, 206 lines, runs
    the ten `tests/virt` programs as processes to the board's
    expectations, and kills `fault.ll` as the IR harness does. The
    compiler, as its process, compiles itself to the same bytes in 7 s:
    6 s under the IR harness, 5 s bare. 8,864 page faults, 4 KB each
  - **Tests:** `tests/virt/user_mode` and six `user_` error tests on the
    board, marked `.board` so they are not run as processes;
    `tests/io/user_absent` and `user_order` here; eight checker cases in
    `check_errors`. Suites: 65, 140, and `--virt` 105, from 86, in 146 s
  - 0079's Why is now writable: this kernel, taught to run a second
    process, with `spin.l0` as that one.
- 2026-10-09: passed on Linux arm64 (65, 140). Done.
