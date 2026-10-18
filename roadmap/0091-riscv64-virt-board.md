# 0091: the riscv64 virt board, and the tests on both CPUs

Kind: language
Status: done, changelog "The virt board and the process host on riscv64"
and "Every L0 function has the fast calling convention"; passed on Linux
arm64 and amd64
Needs: 0090

## Why

0087's route, steps 4 to 8, done as one item: the user asked for the
hosts without an operating system on `qemu-system-riscv64` as well as
`qemu-system-aarch64`. After 0088, 0089, and 0090, what was left was the
riscv64 CPU's part, its board's part and drivers, the process host, the
harness kernel, and the tests' plumbing to run on two CPUs.

## Done when

- spec 10.3 has the riscv64 board, its context, its interrupts, the
  riscv64 process host, and system call 11; 6.16 numbers riscv64 2; the
  changelog says why
- `runtime/arch/riscv64/boot.ll` and `proc.ll`, `runtime/dev/ns16550.ll`
  and `plic.ll`, `runtime/board/virt-riscv64.ll` and `.ld`, and the two
  manifests
- `lib/io.l0` reads riscv64 contexts; the L0 kernel and both harness
  kernels answer call 11; `tests/virt/proc/harness/riscv64/`
- `tools/test.sh --virt` and `tools/bootstrap.sh --virt` run on both
  CPUs, with per-CPU expectations, board constants, and per-CPU tests
- `tools/test.sh`, `--compiled`, and `--virt` green; the seed refreshed if
  the compiler's output changed; Linux arm64 and amd64 green

## Log

- 2026-10-18: written. The board's parts, the harness kernel, and the
  test plumbing (`tests/virt/board/virt-ARCH.l0`, `<stem>.ARCH.ext`,
  `tests/virt/ARCH/`, `<stem>.refused`) in. The first riscv64 run passed
  102 of 105, but the compiler crashed compiling itself on the board, a
  null `Ctx` in `check_call`. Found: LLVM 23's RISC-V back end, for a
  `musttail` call whose arguments do not all fit in registers, writes the
  stack words at the bottom of the caller's own frame, which the call
  frees, instead of into the caller's incoming words, at -O0 and -O2, with
  a frame pointer or without; the callee reads stale words. The
  compiler's components are 9 and 10 words wide, and the C convention
  passes 8 in registers. aarch64 is right. LLVM's `fastcc` passes 13 on
  RISC-V, so every L0 function is now `fastcc` (spec 10.2, changelog
  "Every L0 function has the fast calling convention"), and a riscv64
  target refuses a tail call of more than 13 words when the program is
  built. With it, `emit_tail`, which failed, passes on riscv64, aarch64,
  and the host. Also found: QEMU's 16550 faults a 4-byte access, so
  `region_range` reads a virtio transport, which takes one on both boards.
- 2026-10-18: the L0 kernel's processes on riscv64 needed more frames
  than 1 GB left (`reclaim`, 380 MB of heap, and `stack`, 256 MB), so the
  board runs with 3 GB, its pool in the 5th gigabyte, given by board hooks
  since medany code cannot reach it by address. The serial driver hung on
  riscv64: a PLIC source raised while disabled is never taken once
  enabled, there, so the L0 kernel has call 262, listen, which the driver
  makes before arming its UART, and drives a 16550 as well as a PL011 by
  its third argument. The L0 kernel names a fault's registers by
  `(machine)`, as the harness kernels do. Seed refreshed for `fastcc`;
  fixpoint holds. Suites green: 65, 147, and `--virt` 279 passed, 88
  skipped, 0 failed, on both CPUs, in 382 s; Linux arm64 and amd64 65 and
  147. Done.
