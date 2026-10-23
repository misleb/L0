# 0106: the aarch64 virt board gives PCIe's interrupts, INTx and MSI

Kind: language
Status: done, changelog "The aarch64 virt board gives PCIe's interrupts,
INTx and MSI"
Needs: 0101

## Why

L0S asked for it in `probes/usb/REQUEST-pcie-interrupts.md` there. Its
`xhci` and `sdhci` drivers poll, since no PCIe interrupt is the board's:
`xhci` wakes every millisecond for ever. L0S's
`probes/usb/irq_virt_test.l0`, under `l0 test --target virt`:

```
(def test_intx_b () int (check_int "INTB" (interrupt_enable 36) 0))
(def test_msi_first () int (check_int "MSI 80" (interrupt_enable 80) 0))
```

```
not ok 2 - test_intx_b
  # not ok INTB
  #   got:  -3
  #   want: 0
```

and so for all six of 35 to 38, 80, and 143. Only the host decides what
is an interrupt.

## The plan

- spec 10.3: the aarch64 board's interrupt table gains 35 to 38, INTA to
  INTD, level, and 80 to 143, the GICv2m frame's MSI SPIs, edge; the PCIe
  paragraph says how a function reaches each, the swizzle and the
  address 0x08020040
- `runtime/board/virt-aarch64.ll`: the two ranges, and an MSI made
  edge-triggered before it is enabled, by `l0_gicv2_edge` in
  `runtime/dev/gicv2.ll`
- `tools/test.sh`: a board test's `<stem>.qemu` adds QEMU arguments
- test: `tests/virt/aarch64/pcie_irq`, QEMU's `edu` device at 00:01.0,
  its interrupt taken by INTB and then by MSI 80
- the Pi 5 and the riscv64 board unchanged; L0S leaves them for later

## Done when

- the checklist in the `l0-bootstrap` skill
- `tools/test.sh --virt` green; no Linux run, since nothing a Linux
  program links changes
- L0S's `irq_virt_test.l0` passes under `tools/l0 test --target virt`

## Log

- 2026-10-23: opened from L0S's request, and started.
- 2026-10-23: implemented as planned. The test's first boot hung: the
  board's default network card, `virtio-net-pci`, is 00:01.0, so the test
  wrote another function's BAR; its `.qemu` now says `-nic none`, as L0S's
  demo does, and each wait has a timer deadline, so a lost interrupt fails
  rather than hangs. Taken: 36 by INTB, then 80 by MSI, which INTx could
  not give. No compiler change, so no seed refresh. L0S's
  `irq_virt_test.l0` passes, 6 of 6. Next: tell L0S.
