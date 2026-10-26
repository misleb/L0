# 0123: idle CPUs halt, woken by the host's own SGI

Kind: language
Status: done, changelog "Idle CPUs halt"; not run on a Pi 5, Linux, or
riscv64's half of `--virt`
Needs: 0121

## Why

L0S's `probes/smp/REQUEST-idle-cpus.md`: with 0121, L0S's kernel hands
its processes to the other CPUs, and every board test passes on one CPU
and on four, but on QEMU four CPUs are several times slower than one.
Its e2e case `rootboot_tmpfs`, thousands of messages between the file
server and `install`, takes 47 s on one CPU, 113 s on two, and 222 s on
four, 204 s of it in the host's kernel, so L0S boots its demo and tests
with one CPU and leaves the several-CPU kernel unexercised by everything
that boots for real.

Every waiting CPU waits by `wfe`, which QEMU's TCG runs as a yield
through its main loop and its global lock: each idle vCPU spins on that
lock, and the one with work waits for it at every device access.

Nothing in a program can be written differently to avoid it; the wait is
the host's.

## Done when

- the checklist in the `l0-bootstrap` skill (no seed refresh: the host
  interface is not the seed's)
- spec 6.18's "no interrupt sent between the CPUs" and 10.3's account of
  how a CPU waits; changelog "Idle CPUs halt"
- another CPU polls its ring for a while, then says it sleeps and `wfi`s;
  `cpu_run` to a sleeping CPU sends it an SGI; CPU 0's `cpu_wait` does the
  same, woken by a CPU that gives a thread back or by a device
- a board test that hands threads to a CPU that has gone to sleep, and
  waits in `cpu_wait` long enough to sleep, many times
- L0S's `rootboot_tmpfs` timed on 1 and 4 CPUs

## Log

- 2026-10-26: opened from L0S's request. Next: spec, changelog, runtime.
- 2026-10-26: done. Spec 6.18 and 10.3, changelog, runtime (board.ll's
  poll-then-sleep and its wake, gicv2.ll's SGI 0 sent, and taken as
  spurious, ISR_EL1 before GICC_IAR in `cpu_wait`, the event stream and
  `wfe`/`sev` gone), and `tests/virt/aarch64/cpus_sleep` under `-smp 4`.
  `tools/test.sh` 65, `--compiled` 157, `--virt` on aarch64 187 green; a
  Pi 5 and a riscv64 image link. No seed refresh: only host functions
  changed. L0S's `rootboot_tmpfs` on four CPUs: 222 s to 98 s, system
  time 204 s to 15 s; still twice one CPU's 48 s, which the changelog's
  measurements leave to L0S to place. Not run: a Pi 5, Linux, riscv64's
  QEMU (not installed).
