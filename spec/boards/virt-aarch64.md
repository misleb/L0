# QEMU's aarch64 virt board

Part of the specification of L0, with [L0.md](../L0.md) and
[runtime.md](../runtime.md): what the host of section 10.3 gives on QEMU's
aarch64 `virt` board, its devices and its interrupts. Normative.

## Devices

The devices a region may cover (section 6.12), as QEMU's virt board places
them, all but its interrupt controller, which the host drives itself
(below):

| Base | Bytes | Device |
| --- | --- | --- |
| 0x09000000 | 0x1000 | the PL011 serial port, also standard output |
| 0x09010000 | 0x1000 | the PL031 real-time clock |
| 0x09020000 | 0x18 | the firmware configuration interface |
| 0x09030000 | 0x1000 | the PL061 GPIO controller |
| 0x0A000000 | 0x4000 | 32 virtio-mmio transports, 0x200 bytes each |
| 0x10000000 | 0x2EFF0000 | the PCIe 32-bit MMIO window, where a driver puts the BARs |
| 0x4010000000 | 0x10000000 | the PCIe ECAM, the configuration space of 256 buses, 1 MB each |

where the ECAM is QEMU's high one, as it places it with high memory,
which `l0 boot` leaves on. The host sets nothing of PCIe up: what each
BAR is assigned, and whether a function answers in memory space or
masters the bus, is a driver's to write through the ECAM, and a range
of the window that no BAR holds answers as QEMU decides. The PCIe
port-I/O window and the 64-bit MMIO window are none of the board's, and
so are no region. A function's interrupts are the board's, below, by
either of two routes, and which it uses is its driver's to set through
the ECAM: its interrupt pin, one of the host bridge's four lines INTA to
INTD, which every slot shares, the line a function raises being its pin
turned by its slot, INTA for pin 1 at slot 0 and INTB at slot 1, as
QEMU's `gpex` swizzles it; or an MSI, which the function raises by
writing a number from 80 to 143 to the address 0x08020040, the GICv2m
frame's `MSI_SETSPI_NS`, and which is that number's interrupt. A driver
writes that address and number into its function's MSI or MSI-X
capability, and turns on its bus mastering, since the write is the
function's; the frame itself stays the host's (6.14).

## Interrupts

The interrupts of section 6.14 the host gives, and how it drives the
interrupt controller.

The aarch64 virt board's host drives the board's GICv2 itself, its distributor at
0x08000000, its CPU interface at 0x08010000, and its GICv2m frame at
0x08020000, so none of them is a region, and no program can disable or
take an interrupt behind it. It runs the program with interrupts masked
and its threads with them unmasked, takes an interrupt by reading the
CPU interface's acknowledge register, never reports a spurious one, and
ends one by writing the end-of-interrupt register. Its timer is the
generic timer's virtual timer, whose compare value is the deadline, at
`cntfrq_el0` counts a second. It gives these interrupts:

| Number | Interrupt | The GIC's ID |
| --- | --- | --- |
| 0 | the virtual timer's | 27 |
| 33 | the PL011's | 33 |
| 34 | the PL031's | 34 |
| 35 to 38 | the PCIe host bridge's INTA to INTD | 35 to 38 |
| 39 | the PL061's | 39 |
| 48 to 79 | the virtio-mmio transports', in order | 48 to 79 |
| 80 to 143 | the PCIe MSIs, by the number a function writes | 80 to 143 |

Each is level-sensitive, staying pending while its device holds its
line, so a driver clears its device's cause before it ends one (6.14),
but for the MSIs, which the GICv2m frame raises for QEMU's SPIs 48 to
111, as its `MSI_TYPER` says. The host makes those edge-triggered as it
enables each: a write pends it once, a write while it is taken pends it
again for after its end, and none is lost.
