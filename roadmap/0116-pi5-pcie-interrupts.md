# 0116: the Raspberry Pi 5's PCIe interrupts, RP1's among them

Kind: language
Status: done, changelog "The Raspberry Pi 5 gives PCIe's MSIs, RP1's
among them"
Needs: 0114

## Why

A driver for one of RP1's devices (USB, Ethernet, GPIO, its UARTs) can
reach its registers since 0114, but can only poll: spec 10.3's interrupt
table for the Pi has the virtual timer, the system timer, and the debug
UART, and nothing from PCIe. The aarch64 virt board got its PCIe INTx and
MSIs in 0106; the Pi's are a different path.

From the board's device tree (`bcm2712-rpi-5-b.dtb`): RP1's controller,
`pcie@1000120000`, has INTA to INTD at SPIs 0xE5 to 0xE8 (GIC IDs 261 to
264) and its own "pcie" and "msi" lines at 0xE9 and 0xEA; its `msi-parent`
is `mip0`, `brcm,bcm2712-mip` at 0x1000130000 (0xC0 bytes, and a page at
PCI 0xFF_FFFFF000 for the doorbell), whose `msi-ranges` give SPIs 0x80 up,
64 of them (GIC IDs 160 to 223). RP1 raises its peripherals' interrupts as
MSI-X writes to that doorbell. None of this is a region or an interrupt.

## What is not known

The MIP's registers and what the firmware leaves set in it; whether RP1's
MSI-X table needs programming by the driver or the firmware leaves it;
whether the controller's MSI target registers need setting for the
doorbell; whether INTx works on RP1 at all. Linux's
`irq-bcm2712-mip.c` and RP1's datasheet are the sources to read first.

## Done when

- research: the MIP's registers and RP1's MSI-X path, written into this
  item, with what the firmware leaves read on the board
- spec 10.3: the interrupts a Pi 5 program gets from PCIe, and whatever
  regions the path needs (the MIP), with a changelog entry
- the board's part enables them; a test in `tests/virt/pi5`; suites green
- on the board: an RP1 device's interrupt taken by `interrupt_wait`, for
  example a GPIO edge or RP1's UART's transmit

## Log

- 2026-10-25: started. From Raspberry Pi's Linux (rpi-6.12.y):
  `irq-bcm2712-mip.c` has twelve registers at mip0, 0x1000130000: RAISE
  0x00, CLEAR 0x10, CFGL/H_HOST 0x20/0x30, MASKL/H_HOST 0x40/0x50,
  MASKL/H_VPU 0x60/0x70, STATUSL/H_HOST 0x80/0x90, STATUSL/H_VPU
  0xA0/0xB0. At start it writes host masks 0, VPU masks ~0, and host CFG ~0
  (edge). A message is address 0xFF_FFFFF000 (the MIP's second `reg`),
  data n for vector n, 0 to 63, which is SPI 0x80 + n, GIC ID 160 + n,
  edge. The controller's `dma-ranges` map PCI 0xFF_FFFFF000 to CPU
  0x10_0013_0000, the MIP's own page. `drivers/mfd/rp1.c`: RP1 raises its
  61 interrupts as MSI-X vectors 0 to 60, one each; it programs the
  standard MSI-X table (address and data), and per vector `MSIX_CFG(n)` at
  RP1's PCIE_APBS, 0x108000 in its peripherals, offset 0x8 + 4n, with
  bit 0 ENABLE, bit 3 IACK_EN for a level interrupt, and bit 2 IACK
  written after each one is handled; set and clear aliases at +0x800 and
  +0xC00. So the MIP and the GIC are the host's, and RP1's table and
  `MSIX_CFG` are a driver's, through RP1's region and the controller's.
  A probe, `tmp/0116/mip.l0`, with a copy of the board part that opens the
  MIP, is built to read on the board: the MIP as the firmware leaves it,
  the controller's 0x4000 to 0x41FC (inbound windows), RP1's config space
  (where its MSI-X table is), and `MSIX_CFG`. Next: run it, once the TFTP
  server serves `tmp/pi5/tftp`.
- 2026-10-25: run on the 2 GB board. `mip0`'s registers all 0 (level,
  open to the VideoCore); the controller's inbound windows: RC_BAR2 PCI 0
  for 64 GB onto RAM, RC_BAR1 and RC_BAR3 off, nothing at 0x40D4 up, its
  own MSI target on at 0xF_FFFFFFFC; RP1's MSI-X at 0xB0, 61 vectors, off,
  table at BAR0 offset 0 and pending bits at 0x2000, BAR0 at PCI
  0x80410000; `MSIX_CFG` all 0. A second probe, its board part setting
  RC_BAR3 to `mip0` and `mip0` as Linux does: BAR0 is 16 KB and BAR2 64
  KB; a CPU write of 0 to `mip0` was taken as 160, and RP1's vector 0,
  given the doorbell and 1 and raised by its test bit, as 161. Spec 10.3,
  changelog "The Raspberry Pi 5 gives PCIe's MSIs, RP1's among them", the
  board part, `lib/AGENTS.md`, `tests/virt/pi5/msi`, and `rp1` for the
  region's new end; both run on the board with the real part and match
  their `.out`. Not done: an interrupt from one of RP1's devices rather
  than its test bit (the last Done-when line), and INTx, left out. Next:
  the suites, then a device's interrupt, RP1's UART or a GPIO edge.
- 2026-10-25: done. `tools/test.sh` and `--compiled` green; `--virt`
  green on aarch64 and the Pi 5's build checks, its riscv64 half not run
  here (no `qemu-system-riscv64`), and nothing riscv64 links changed. No
  compiler change, so no seed refresh; no Linux run, since nothing a Linux
  program links changed. A device's interrupt, on the board: GPIO 27's
  input overridden low then high gave nothing, since the bank's detectors
  watch the pad (STATUS 0x04480000: INTOPERI high, the pad's LOW events);
  its level-low detector on the unconnected pin raised RP1's IO_BANK0 as
  162, STATUS 0x34400000 and PCIE_INTS bit 27, both gone once IRQEN_LOW
  was cleared and IACK written. Kept as `tests/virt/pi5/gpio_irq`. Left
  out: INTx and the controller's own MSI target, until a program needs
  them. Next: tell L0S, whose USB stack on the Pi polls.
