# 0119: a program can restart its board

Kind: language
Status: done, changelog "A program can restart its board"; no run on a
Pi 5, no Linux or riscv64 run here
Needs: nothing

## Why

L0S's `probes/driver/REQUEST-pi5-reboot.md`: on the Raspberry Pi 5 its shell
can end the system with `exit`, which halts the board, and nothing in L0
restarts it, so each test boot needs the power pulled. It asks for
`(board_reset)`, never returning, by PSCI `SYSTEM_RESET` by `smc`; the
power manager as a region is an alternative it would also welcome.

## Done when

- the checklist in the `l0-bootstrap` skill, and the seed refreshed
- spec 6.12, 9.2, 10.3; changelog "A program can restart its board"
- `tests/io/board_reset` (-3 on a host), `tests/virt/aarch64/board_reset`
  (QEMU exits under `-no-reboot`), `tests/virt/riscv64/board_reset` (-3)
- the pi5 target builds; a run on a Pi 5 is the user's: after `reboot` the
  bootloader should fetch the program again, not stop at `Halt:`

## Log

- 2026-10-25: opened from L0S's request; builtin chosen over the region
  (changelog). Spec, changelog, compiler, runtime, and tests written.
  `tools/test.sh` 65 and `--compiled` 156 green; `--virt` on aarch64
  (L0_VIRT_LD=ld.lld, no Docker here) 179 passed, including
  `board_reset`, where QEMU under `-no-reboot` exits at the SMC; seed
  refreshed; a Pi 5 image with the call links. Not run: Linux
  (`tools/linux-test.sh` needs Docker), riscv64's half of `--virt` (no
  qemu-system-riscv64), a Pi 5. Next: L0S uses it in `sh`'s `reboot`.
