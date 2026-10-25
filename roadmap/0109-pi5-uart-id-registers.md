# 0109: the Pi 5's UART test must not expect PL011 ID registers

Kind: language
Status: done, changelog "The Pi 5's debug UART has no identification
registers"; run on a Pi 5; riscv64's half of `--virt` not run, see the Log
Needs: nothing

## Why

0098 planned the Pi's UART region as 0x1000 bytes so that the PL011's
PrimeCell ID registers are reachable, and `tests/virt/pi5/uart.l0` reads
PeriphID0 (0xFE0) and PrimeCell ID3 (0xFFC) expecting `11` and `b1`. On a
Pi 5 (serial 1b08af2e, EEPROM 2026/05/26), booted by TFTP, it printed:

```
hi from the pi
0
0
```

The writes reached the port; the two reads gave 0. So on the BCM2712's
debug UART the ID registers are not there to read, and `uart.out` holds
what only QEMU gives. The program is the code that cannot pass as written.

## Done when

- the finding is in spec 10.3 where the Pi's UART is described: what the
  region is for and that its ID registers read 0 on the board, so a driver
  must not probe by them
- the changelog says why the region stays 0x1000 or shrinks, with the run
  as evidence
- `tests/virt/pi5/uart.l0` and `.out` expect what the board does, and say
  in their header that the expectation is from a run on a Pi 5; `--bless`
  is not used, its `git diff` is read
- `tools/test.sh`, `tools/test.sh --compiled`, and `tools/test.sh --virt`
  green, plus a second run on the board through 0108's loop once it exists

## Log

- 2026-10-24: opened after 0098's first run. Next: read where spec 10.3
  and the region's size say the registers are reachable, then change them.
- 2026-10-24: the spec never said the registers were reachable; only 0098's
  plan and the test did. A probe (`tmp/0109/probe.l0`, run through 0108's
  loop) read FR 0x90, IBRD 0x18, FBRD 0, LCRH 0x70, CR 0x301, IMSC 0, and
  all eight identification words 0. Spec 10.3 now says so, the changelog
  has "The Pi 5's debug UART has no identification registers", and
  `tests/virt/pi5/uart.l0` and `.out` expect `0`, `0`, and `101` (CR's enable
  bits), by hand, not blessed. Run on the board: its output matches
  `uart.out`. Next: `tools/test.sh`, `--compiled`, and `--virt` green.
- 2026-10-24: `tools/test.sh` 65 passed. `--compiled` 154 passed and 1
  failed, `io/libdoc`: it expects `find | sort` to put `./.cursor` before
  `./AGENTS.md`, which only the C locale does; under `LC_ALL=C` it passes.
  `--virt` here, with `L0_VIRT_LD=/usr/bin/ld.lld` and `L0_VIRT_ARCHS=
  aarch64`: 173 passed, 1 failed, `virt/layout_overlap`, whose
  `.refused` has the linker's line twice where this host's `ld.lld` writes
  it once; riscv64 cannot run, `qemu-system-riscv64` not being installed.
  None of the three touches this change. Left for the user: whether to make
  `libdoc` locale-proof and `layout_overlap` independent of the linker's
  version, and the riscv64 half of `--virt` on a host with QEMU for it.
- 2026-10-24: the user said yes to both fixes. `tests/io/libdoc.sh` sorts
  with `LC_ALL=C`; `tools/test.sh` compares a `.refused` file with its
  adjacent repeated lines written once on both sides, so the linker's
  wording is still pinned and its repeating is not. Default locale:
  `tools/test.sh` 65, `--compiled` 155, and `--virt` on aarch64 174, all
  passed, none failed. riscv64's half of `--virt` has not run here
  (`qemu-system-riscv64` is missing), but nothing in this item touches
  riscv64. Done.
