# 0101: the aarch64 virt board's PCIe ECAM and MMIO window are regions

Kind: language
Status: done, changelog "The aarch64 virt board's PCIe ECAM and MMIO window
are regions"
Needs: nothing

## Why

L0S asked for it in `probes/usb/REQUEST-pcie-rp1-cache.md` there, the first
of three asks (0102 and 0103 are the others). Its USB stack drives an xHCI,
which QEMU's virt board has only as `qemu-xhci` on PCIe. Finding it, sizing
its BAR and turning on its memory space needs the ECAM, and reaching its
registers needs the 32-bit MMIO window, and the board gives neither: spec
10.3 says "any range of the flash, the PCIe windows, or the gaps between
devices" is no region. L0S's `probes/usb/usb_virt_test.l0`, under
`l0 test --target virt`:

```
(def test_ecam_bus_0 () int
  (check_true "a region" (ge (region_open 275146342400 1048576) 0)))
```

```
not ok 1 - test_ecam_bus_0
not ok 2 - test_mmio_window
not ok 3 - test_mmio_window_end
```

No program can work around it: only the host decides what is a region.

## The plan

- spec 10.3: the aarch64 board's table gains the ECAM, 0x4010000000 and
  0x10000000 bytes, and the 32-bit MMIO window, 0x10000000 and 0x2EFF0000
  bytes, where QEMU puts them with high memory, as `l0 boot` runs it
- `runtime/board/virt-aarch64.ll`: the two devices; the boot map's block
  256, 0x4000000000, Device-nGnRnE, which holds the ECAM, and a space's
  root table's the same, for EL1 alone. The window is in block 0 already
- the IR harness kernel's copy of the table, `tests/virt/proc/harness/
  aarch64/kernel.ll`, and its TCR's physical addresses 40 bits, from 32,
  so a region page can map the ECAM
- tests: `tests/virt/aarch64/pcie`, on the board and as processes, reading
  the host bridge's vendor and device from bus 0's configuration space and
  opening the window's first and last pages, with ranges past either's end
  no region
- the riscv64 board is unchanged: nothing has asked for its PCIe

## Done when

- the checklist in the `l0-bootstrap` skill
- `tools/test.sh --virt` green; no Linux run, since nothing a Linux
  program links changes
- L0S's `usb_virt_test.l0` passes under `tools/l0 test --target virt`

## Log

- 2026-10-21: opened from L0S's request, and started.
- 2026-10-21: implemented as planned. Under the IR harness kernel the test
  first printed nothing: its TCR gave 32-bit physical addresses, so a page
  at the ECAM could not be mapped; it gives 40 now, as the board's boot
  code does. No compiler change, so no seed refresh. Suites green: 65,
  151, `--virt` 318 passed, 88 skipped. L0S's `usb_virt_test.l0` passes
  under `tools/l0 test --target virt`. Next: tell L0S, whose Part B can
  start; then 0102.
