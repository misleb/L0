# The Raspberry Pi 5

Part of the specification of L0, with [L0.md](../L0.md) and
[runtime.md](../runtime.md): what the host of section 10.3 gives on the
Raspberry Pi 5, its devices and its interrupts. Normative. What here says
a board run read or did was read on a 2 GB board.

## Devices

The devices a region may cover (section 6.12), all above 4 GB, the GIC-400
not a region (below):

| Base | Bytes | Device |
| --- | --- | --- |
| 0x107D001000 | 0x1000 | the debug UART, a PL011, also standard output |
| 0x107C003000 | 0x1000 | the 1 MHz system timer |
| 0x107C013880 | 0x40 | the VideoCore mailbox |
| 0x1F00000000 | 0x414000 | RP1's peripherals, its two USB controllers among them, through the PCIe link the firmware set up, its BAR1, 0x400000 bytes; then its BAR2 and BAR0, where a program puts them (below) |
| 0x1000120000 | 0x9310 | the PCIe controller RP1 is behind, `brcm,bcm2712-pcie`: its registers, and the configuration space of the devices behind it through its index and data registers |
| 0x107C580000 | 0x1A000 | the HVS, the display's compositor, its registers and from 0x4000 its display list memory |
| 0x1000005200 | 0x80 | `iommu4`, the IOMMU through which the HVS reads memory |
| 0x1000005B00 | 0x80 | `iommuc`, the cache the IOMMUs share |
| 0x107C700000 | 0x4800 | HDMI0's blocks, in one run: the DVP clock and reset controller (0x0), the CSC (0x100), the DVP (0x1000), the HDMI core (0x1400), the PHY (0x1D00), the rate manager (0x2000), packet RAM (0x3800) and metadata (0x4000) |
| 0x107C720000 | 0x100 | the HD block both HDMIs share, with `VID_CTL` |
| 0x107C410000 | 0x100 | pixel valve 0, which feeds HDMI0 from the HVS's channel 0 |
| 0x107D508200 | 0x58 | DDC0, a `brcm,brcmstb-i2c` controller on HDMI0's DDC lines |
| 0x1000010600 | 0x100 | channel 6 of `dma40`, the 40-bit DMA controller, `brcm,bcm2712-dma` |
| 0x1000FFF000 | 0x600 | `sdio1`, the SD host controller behind the microSD slot, `brcm,bcm2712-sdhci`: SDHCI's registers, then at 0x400 the brcmstb `cfg` block |
| 0x107C502000 | 0x30 | `disp_intr`, the display's interrupt controller, `brcm,bcm2711-l2-intc`, through which the HVS raises its channels' ends of frame |

The debug UART is as the firmware leaves it, enabled with transmit and
receive on, 8-bit words and FIFOs, and no interrupt enabled. Unlike
QEMU's PL011, its identification registers, PeriphID0 to 3 and PrimeCell
ID0 to 3, at 0xFE0 up to 0x1000, all read 0, so a driver takes it to be a
PL011 from the device tree, not by probing.

The HVS is as the firmware leaves it, scanning out HDMI0 in the mode the
firmware chose, when a monitor was on HDMI0 as the board booted; the
host sets nothing of the display up, and drives none of its interrupts.
With no monitor there, a read of the HVS's registers hangs the board,
with no fault taken, though `l0 card`'s `config.txt` says
`hdmi_force_hotplug=1`: a program reads the HVS only on a board that
booted with a monitor, which the firmware's log shows as `hotplug 1`.
The two IOMMUs share a page with others, `iommu2` and `iommu5` among
them, which are no region, as the mailbox shares one.

`disp_intr` is a region, and its interrupt, 129 below, is given, so
that a program can learn when the HVS has finished a frame rather than
poll for it: the HVS has no end-of-frame register of its own, and
raises each channel's end of frame as a line of this controller,
channel 0's line 2, channel 1's 9, and channel 2's 16. It is level:
the lines raised are at 0x00, a write of 1s at 0x08 clears them, the
mask is at 0x0C, a write of 1s at 0x10 masks lines and at 0x14 unmasks
them. It is as the firmware leaves it, and the host sets nothing of it
up: a driver masks the lines it does not take, unmasks its channel's,
and clears each line it takes at 0x08 before `interrupt_done`. Its
clock is the display's, so a program reads it only where it may read
the HVS.

HDMI0's controller, PHY, pixel valve, and DDC are regions so that a
program can set the mode itself rather than take the firmware's. The
host sets none of them up and drives none of their interrupts (HDMI0's
hotplug, `aon_intr`, and DDC0's, `bsc_irq`, are not offered). Their
clocks are the firmware's, asked over the mailbox. The HDMI blocks stop
the CPU with no fault when read while their clock, the mailbox's M2MC,
is at 0, as the HVS does unclocked: a program sets that clock first.

Channel 6 of `dma40` is a region so that a program can feed HDMI0's
audio FIFO, the MAI in the HD block, at the rate the monitor plays it,
without the CPU. It is as the firmware leaves it, and the host sets
nothing of it up. Its control blocks and the memory it reads and
writes are at the CPU's addresses, as the device tree's identity
`dma-ranges` say, so a frame's address (6.13) is the channel's. Its
interrupt, 118 below, is level, and a driver ends it by writing bit 2,
`INT`, to the channel's `CS` before `interrupt_done`. The other channels
are no region: 7 to 10 are Linux's and not yet asked for, and 11 is the
firmware's, for VCHIQ. A channel writes wherever its control blocks
say, so a program that opens it can write any memory, as the HVS can
through `iommu4`.

`sdio1` is a region so that a program can read and write the microSD
card. It is a standard SDHCI, its registers SDHCI's own, its base clock
a fixed 200 MHz should its capabilities not say it, and the brcmstb
`cfg` block after them sets how the card is detected and the
controller's speed straps. It is as the firmware leaves it, and the
host sets nothing of it up. The card's power, its signalling at 3.3 V,
and its detect pin are `gio_aon`'s, which is no region, and are as the
firmware leaves them. Its interrupt, 305 below, is level, and a driver
ends it by writing back the status bits it handled, in Normal and Error
Interrupt Status (0x30), before `interrupt_done`. Its SDMA and ADMA2
can write memory wherever a program says, as a `dma40` channel can; at
what bus address it reaches memory no board run has yet said.

RP1 is behind PCIe, through the controller above, and the host sets
nothing of PCIe up but the path of its MSIs, below. With `l0 card`'s `config.txt` asking the firmware to
leave the link, `pciex4_reset=0`, the link is up, and RP1 is a device the
firmware has enumerated: but its window at 0x1F00000000 reads 0xDEADDEAD
throughout, without a fault, because the firmware left the controller
set for a different address: the root port's bus numbers 0, so that
bus 1 is not decoded; RP1's BAR1 at PCI address 0x80000000; and the
controller's outbound window, PCI 0x80000000 from CPU 0x1C00000000 for
1 GB, not from 0x1F00000000. A program makes the window answer through
the controller's registers, which are a region for that, and a board run
read RP1's chip ID, 0x20001927, at the window's start after it set the
root's bus numbers to 0, 1, 1, its memory window to 0 up to 0x3FFFFF,
RP1's BAR1 to 0, and the outbound window to PCI 0 from CPU
0x1F00000000. A device on RP1 reaches the board's memory at a bus address
0x1000000000 above the CPU's, which is its driver's to add: a frame's
address (6.13) is the CPU's.

A function behind the controller raises an MSI by writing a number n
from 0 to 63 to the bus address 0xFF_FFFFF000, which is interrupt 160 +
n (below). That address is `mip0`'s, `brcm,bcm2712-mip`, at
0x1000130000, which turns a write into one of the GIC's SPIs, and
which, like the GIC, is the host's and no region. The firmware maps no
bus address to it, so the host does as it starts: the controller's
third inbound window, its registers 0x403C and 0x4040 and their remap
0x40BC and 0x40C0, takes 0xFF_FFFFF000, 4 KB, to 0x1000130000, and a
program leaves those four registers as they are. The firmware leaves
`mip0`'s vectors level-triggered and open to the VideoCore as well; the
host makes them edge-triggered and the CPU's alone. The controller's
four INTx lines and its own MSI target, which the firmware sets at
0xF_FFFFFFFC, are no interrupt of the board's.

RP1 raises its 61 interrupts as MSI-X vectors 0 to 60. Its MSI-X table
is in its BAR0, 16 KB, at offset 0, and its pending bits at 0x2000, and
BAR2, 64 KB, lies before it: a program reaches both in RP1's region by
setting, as well as the above, the root's memory window to 0 up to
0x4FFFFF, BAR2 to PCI 0x400000, and BAR0 to 0x410000, so that the table
is at 0x1F00410000. For vector v, a driver writes table entry v, 16
bytes at 16 v, as the address 0xFF_FFFFF000, its low and high words,
the number n, and 0 to unmask it; sets bit 31 of the word at RP1's
configuration offset 0xB0, MSI-X's enable; and sets bit 0, enable, of
RP1's `MSIX_CFG` for v, the word at 0x108008 + 4 v in RP1's region,
through its set alias at +0x800 (and its clear alias at +0xC00). For a
level-triggered source, it sets bit 3 there too, and writes bit 2 after
each interrupt is handled, which acknowledges it so that RP1 sends the
next. Bit 1 raises v as a test. A board run took RP1's vector 0 so,
with n 1, as interrupt 161, raised by its test bit, and, with n 2, as
interrupt 162, raised by its GPIO bank for a pin's level.

## Interrupts

The interrupts of section 6.14 the host gives, and how it drives the
interrupt controller.

The Raspberry Pi 5's host drives its GIC-400, a GICv2, the same way, its
distributor at 0x107FFF9000 and its CPU interface at 0x107FFFA000, no
region either; the firmware leaves every interrupt in the non-secure
group, so the host asks for nothing more. Its timer is the virtual
timer, at `cntfrq_el0`, 54,000,000 counts a second. It gives these
interrupts:

| Number | Interrupt | The GIC's ID |
| --- | --- | --- |
| 0 | the virtual timer's | 27 |
| 96 to 99 | the system timer's four | 96 to 99 |
| 118 | `dma40`'s channel 6's | 118 |
| 129 | `disp_intr`'s, the HVS's ends of frame among its lines | 129 |
| 153 | the debug UART's | 153, or 152 on the later silicon, so the host enables both and reports either as 153 |
| 160 to 223 | the PCIe MSIs, by the number n a function writes, 160 + n, through `mip0` | 160 to 223 |
| 305 | `sdio1`'s | 305 |

The MSIs are edge-triggered, as on the virt board, and the others level.
