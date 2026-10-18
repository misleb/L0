# 0088: tooling: a host without an operating system, in parts

Kind: tooling
Status: done, changelog "A host without an operating system is made of
parts, and no language change for it"
Needs: 0087

## Why

0087's first step. `runtime/host-virt.ll` was one file of 1,754 lines in
which aarch64's boot code and descriptors, QEMU's memory map, the GICv2,
the PL011, semihosting, the device tree, the frame pool, and the interrupt
bookkeeping were one thing, and `runtime/host-proc.ll` mixed `svc` with
the system calls. The tools named both files and aarch64 throughout. A
riscv64 board, and later the VisionFive 2 and the Pi 4, would each have
been a copy of all of it.

## Done when

- `runtime/bare/board.ll`, `runtime/bare/semihost.ll`,
  `runtime/arch/aarch64/boot.ll`, `runtime/dev/gicv2.ll`,
  `runtime/dev/pl011.ll`, and `runtime/board/virt-aarch64.ll` and `.ld`
  replace `host-virt.ll` and `virt.ld`; `runtime/bare/proc.ll` and
  `runtime/arch/aarch64/proc.ll` replace `host-proc.ll`
- a manifest per target, `runtime/targets/NAME.target`, which
  `tools/targets.sh`, `build.sh`, `install.sh`, and `tools/l0` read;
  `--arch`, aarch64 by default; `l0 boot` picks the board from the image's
  boot header; `L0_RUNTIMES` replaces `L0_VIRT_DIR` and `L0_PROC_DIR`
- spec 10.3 says what the parts are; the changelog says why
- `tools/test.sh`, `--compiled`, and `--virt` green, `--virt` with the same
  136 passes and 43 skips as before

## Log

- 2026-10-17: started. Baseline `--virt`: 136 passed, 43 skipped, in 173
  s. Split written: the neutral part holds the frame pool and the walk
  over hooks for arm64's descriptor bits, and decides "a frame" by the
  pool's range rather than arm64's attribute index; the board's part holds
  the boot map, a new space's root entries, the device table, and the
  interrupt numbers; drivers take their base address. Spec 10.3 renamed
  its files; changelog "A host without an operating system is made of
  parts, and no language change for it".
- 2026-10-17: suites green: 65, 146, and `--virt` 136 passed and 43
  skipped, as before, in 180 s. No compiler change, so no new seed. Done.
  Next: 0089.
