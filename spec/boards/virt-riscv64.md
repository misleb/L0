# QEMU's riscv64 virt board

Part of the specification of L0, with [L0.md](../L0.md) and
[runtime.md](../runtime.md): what the host of section 10.3 gives on QEMU's
riscv64 `virt` board, its devices and its interrupts. Normative.

## Devices

The devices a region may cover (section 6.12), as QEMU's virt board
places them, all but its PLIC, at 0x0C000000, and its CLINT, which the SBI
drives, which are no regions:

| Base | Bytes | Device |
| --- | --- | --- |
| 0x10000000 | 0x100 | the 16550 serial port, its registers a byte apart, also standard output |
| 0x00101000 | 0x1000 | the goldfish real-time clock |
| 0x10100000 | 0x18 | the firmware configuration interface |
| 0x10001000 | 0x8000 | 8 virtio-mmio transports, 0x1000 bytes each |

## Interrupts

The interrupts of section 6.14 the host gives, and how it drives the
interrupt controller.

The riscv64 virt board's host drives its PLIC itself, in the context of
the booting hart's S-mode, giving every source it enables priority 1 and
the context threshold 0, so that of several pending the lowest number is
claimed first. It runs the program with interrupts masked, `sstatus.SIE`
clear, and its threads in U-mode, where they reach the hart whatever
`SIE` says; it takes a device's interrupt by the PLIC's claim, and ends
it by its completion. Its timer is the SBI's, its deadline set by the
TIME extension's `set_timer`, at the board's timebase, 10,000,000 counts
a second on QEMU, and it takes the timer's interrupt by masking it in
`sie` until it is ended, since it stays pending until a deadline still to
come is set; a timer pending is taken before any device's. It gives
these interrupts:

| Number | Interrupt | The PLIC's source |
| --- | --- | --- |
| 0 | the timer's | none: the supervisor timer interrupt |
| 1 to 8 | the virtio-mmio transports', in order | 1 to 8 |
| 10 | the 16550's | 10 |
| 11 | the RTC's | 11 |
