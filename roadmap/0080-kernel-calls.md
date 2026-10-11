# 0080: a process's calls to its kernel's own system calls

Kind: language
Status: done, changelog "A process calls its kernel's own system calls";
passed on Linux arm64
Needs: 0079

## Why

[0074](0074-route-to-a-microkernel.md)'s item 6, earned by a driver serving
another process. A serial driver that is a process takes the PL011 as a
region and then must ask its kernel for the next bytes any process sent
it, and a client must send them, by calls of the kernel's own, which
spec section 10.3 numbers from 256 (`roadmap/0080/why.l0`):

```
(def serve ((u int)) int                             ; the driver's loop
  (let b (supervisor_call 257 0 0 0)                 ; the next byte sent
    (let w (uart_put u b) (serve u))))

(def send ((b int)) int                              ; a client
  (supervisor_call 256 b 0 0))
```

```
roadmap/0080/why.l0:12:10: error: unknown function supervisor_call
roadmap/0080/why.l0:16:3: error: unknown function supervisor_call
```

`host-proc.ll` makes only the host's ten calls, and nothing in L0 names
another.

## The design

0074's Log: one call from words to words, with the ABI the kernel's own.
The user chose words and bytes over words alone, since the goal's measure
carries the compiler's 1.3 MB of output through a driver that is a
process, which in words would take tens of thousands of calls:

- `(supervisor_call n a b c)`: the kernel's call `n`, with `a`, `b`, and
  `c` in `x0` to `x2`, giving back its `x0`
- `(supervisor_send n a b i j)`: as it, with bytes `i` up to `j` of `b`
  passed as their address in the process and their count
- `(supervisor_receive n a max)`: as it, with room for `max` bytes passed
  the same way, giving back the bytes the kernel wrote there, as many as
  its `x0` says, or none if that is negative
- `n` below 256 is a runtime error, so no program goes around the
  runtime's own calls; on a host that is no process, -3 and no bytes
- what a call means is the kernel's, so the library gives no type over it:
  that belongs to the kernel's project

## Done when

- the checklist in the `l0-bootstrap` skill, and "Adding a builtin" there
- section 6.15 says what each builtin does, with its runtime error;
  section 8, 9.2, and 10.3 as for 0079. The changelog says why
- `host-proc.ll` makes the calls; `l0rt.ll` checks them; `host-libc.ll`
  and `host-virt.ll` give -3
- `tests/virt/user/kernel.l0` answers calls of its own: a serial driver,
  a process, receives what a client process sends and writes it to the
  PL011, the driver blocking while nothing is sent and the client until
  what it sent is written, and the kernel waiting for an interrupt when no
  process can run; `tools/test.sh --virt` runs them
- tests of the absence and the error on this host and the board

## Log

- 2026-10-10: opened from 0074's item 6; the Why above was checked. The
  user chose words and bytes. Next: the spec.
- 2026-10-11: implemented. Section 6.15, three builtins and `system call
  reserved`, 9.2's absence, 10.3's calls and `l0_host_supervisor`; the
  changelog says why. The checker, emitter, `l0rt.ll`, which refuses the
  low numbers on every host, and the three host files. The seed is
  refreshed.
  - **The kernel in L0** holds its state in a `Kern`: the processes, the
    bytes queued, and the device interrupts taken. It answers six calls
    of its own (its header lists them): send, receive, sync, wait for a
    device interrupt, end one, and sleep. A process blocks receiving,
    syncing, waiting, or asleep, and when none can run, the kernel waits
    for an interrupt, the timer's set for the next sleeper
  - **Found on the way:** a driver's own interrupt, the PL011's transmit
    one, arrives while the driver still runs, before it asks to wait for
    it, so the kernel keeps an interrupt no one waited for and gives it
    at the wait. It also means the driver never leaves the kernel idle,
    so sleeping is what tests the idle wait
  - **Tests:** `tests/virt/user/serial` (a client sends two lines, one in
    pieces, through a driver process, which writes them to the PL011 a
    byte at a time, waiting for its interrupt, then syncs);
    `tests/virt/user/sleeper` (asleep alone, woken by the timer, and an
    undefined call and a reserved one); `tests/io/supervisor_absent`
    here and on the board; three checker cases. Tests of the kernel name
    their processes in a `.procs` file, `fault` among them
- 2026-10-11: suites green: 65, 142, and `--virt` 111, from 108, in 159
  s; Linux arm64 65 and 142. Done. 0074's language items are all done;
  what is left of it is item 7, the kernel in its own project, and item
  8, the measure as a test, with the two gaps its Log names first.
