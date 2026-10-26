# 0121: user threads on the other CPUs

Kind: language
Status: done, changelog "Threads run on the other CPUs"; not run on a
Pi 5, Linux, or riscv64's half of `--virt`
Needs: nothing

## Why

L0S's `probes/smp/REQUEST-multiple-cpus.md`: L0S runs every process on
one CPU, and the Pi 5's other three cores, and any QEMU gives, never run
anything, since nothing in L0 starts a CPU or runs a thread on one.
`user_run` is synchronous, and a second CPU could not run L0 code, whose
heap serves one CPU. Its `want.l0`, CPU 0's loop draining traps the other
CPUs posted and filling their rings from one ready queue, is rejected by
`l0 check`: `cpu_count`, `cpu_run`, `cpu_trapped` and `cpu_wait` do not
exist.

It asks for those four: the program stays on CPU 0, the others run user
threads only, handed to them and handed back through single-producer,
single-consumer rings in the runtime's memory, polled, with no
inter-processor interrupt; each CPU takes only its own timer.

## Done when

- the checklist in the `l0-bootstrap` skill, and the seed refreshed
- spec 6 (table), a new 6.18, 6.13's `space_free`, 8's two new errors,
  9.2, 10.3; changelog "Threads run on the other CPUs"
- the aarch64 virt board starts the CPUs its device tree gives by PSCI's
  `CPU_ON` and runs threads on them; `tests/virt/aarch64/cpus` under
  `-smp 4` runs threads on three CPUs at once; one CPU everywhere else
  tested (`tests/io`, riscv64, a process)
- the Pi 5 image links with the same code; a run on a Pi 5 is the user's

## Log

- 2026-10-26: opened from L0S's request. Decided: `cpu_run` borrows its
  context and copies it into the ring, so a kernel may hand the same
  context to another CPU when one ring is full, as `want.l0` does; a `c`
  that is not another CPU is the runtime error `not a CPU`, with no -3,
  since a host without user mode has one CPU and so no `c` to give; the
  run ring and the trap ring of a CPU are one ring of slots with three
  counters; riscv64 starts no other hart yet (cpu_count 1), which the
  request's own "a host that cannot start its other CPUs" allows.
  Spec, changelog, compiler, runtime, and tests written. L0S's `want.l0`
  type checks. `tests/virt/aarch64/cpus` passed on the first boot under
  `-smp 4`: a thread spinning on CPU 1 until CPU 2's thread set a shared
  word came back by its call, not its 2 s deadline, so they ran at once.
  `tools/test.sh` 65 and `--compiled` 157 green; `--virt` on aarch64
  (L0_VIRT_LD=ld.lld) 185 passed; seed refreshed (LLVM-VERSION now this
  host's clang 23.1.4); a Pi 5 image of `cpus` links. Not run: Linux
  (`tools/linux-test.sh` needs Docker), riscv64's half of `--virt` (no
  qemu-system-riscv64), a Pi 5, where `tests/virt/aarch64/cpus` under
  `tools/pi5-run` should print 4 and match its `.out`. Next: L0S's
  `kernel/cpus.l0` and the loop of its request.
