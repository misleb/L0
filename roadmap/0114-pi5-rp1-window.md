# 0114: make RP1 answer on the Raspberry Pi 5

Kind: program
Status: done
Needs: 0113

## Why

0113 made the PCIe controller a region and showed the link up with RP1's
window reading `0xDEADDEAD`. The product of this item is the smallest
sequence of writes that makes the window read RP1, as a program, and
the spec saying what the firmware leaves.

## Done when

- RP1's chip ID, 0x20001927, read through the window on a Pi 5
- the spec and the changelog say what the firmware leaves and what a
  program sets

## Log

- 2026-10-25: done, in four probes under `tmp/0114/` (`cfg.l0`, `bus.l0`,
  `bar.l0`, `win.l0`), each run through `tools/pi5-run`. The root port read
  14e4:2712 with bus numbers 0, so bus 1 read `ffffffff`; set to 0, 1, 1,
  bus 1 device 0 was 1de4:0001 (RP1) with BAR0 0x80410000 and BAR1
  0x80000000. The outbound window was PCI 0x80000000 from CPU 0x1C_0000_0000
  for 1 GB. Setting BAR1 to 0 and the window to PCI 0 from CPU 0x1F_0000_0000
  (0x400C 0, 0x4080 and 0x4084 0x1F) made 0x1F00000000 read 0x20001927 and
  2. Changelog "RP1's window answers once the controller is set".
  Next: the USB controllers' GSNPSID (0102's original check), and a driver
  for them, which is a program item of its own; not opened.
