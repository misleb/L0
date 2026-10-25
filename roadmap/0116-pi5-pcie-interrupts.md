# 0116: the Raspberry Pi 5's PCIe interrupts, RP1's among them

Kind: language
Status: queued
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
