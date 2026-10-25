# 0113: the Raspberry Pi 5's PCIe controller for RP1 is a region

Kind: language
Status: done
Needs: nothing

## Why

0102 made RP1's peripheral window, 0x1F00000000 for 0x400000 bytes, a
region, on the plan that the firmware leaves the link up and the window
answering (`pciex4_reset=0` in `l0 card`'s `config.txt`). Its Log asked a
first run to read each USB controller's xHCI and DWC3 identity. On a 2 GB
Pi 5 (serial 1b08af2e, EEPROM 2026/05/26), booted by TFTP through
`tools/pi5-run`, `tmp/0110/rp1usb.l0` opened both controllers over 64 KB
and read the first word of each and GSNPSID at 0xC120:

```
deaddead      0x1F00200000, CAPLENGTH and HCIVERSION
deaddead      0x1F00200000 + 0xC120, GSNPSID
deaddead      0x1F00300000, CAPLENGTH and HCIVERSION
deaddead      0x1F00300000 + 0xC120, GSNPSID
```

`tmp/0110/rp1id.l0` read 0x1F00000000 and 0x1F00000004 and got `deaddead`
for both, where the firmware's log says RP1's chip ID is 0x20001927 (it
reads it by its own means, before handing the board over). No read
faulted or hung: the window is a live bus address, and answers, but not
with RP1's registers. Whether `deaddead` is a pattern the controller
returns for an unassigned address is not established here.

The device tree's controller is `pcie@1000120000`, `brcm,bcm2712-pcie`,
`reg = <0x10 0x120000 0x0 0x9310>`, and its `ranges` map PCI memory
address 0 up to 0xFFFFFFFC to CPU 0x1F00000000 up: so the window is the
controller's outbound PCI memory space, and RP1's peripherals are in it
only where RP1's BAR1 has been assigned and the controller's outbound
window enabled and translated. Nothing says the firmware leaves that done
at the handoff to an image, and the reads say it did not. That is
configuration, through the controller's registers, at 0x1000120000 for
0x9310 bytes, and config space reached by the controller's index and data
registers inside it. Spec 10.3's table for the Pi has no such region, so
no program can read the link's status, set the window, or assign the BAR:
L0S's `probes/usb` cannot reach its controllers however it is written.

The smallest program that cannot be written today: open
0x1000120000 for 0x9310 bytes and read the controller's status register.

```
(open_device 68720656384 37648)   ; 0x1000120000: no such region, by the
                                  ; spec's table; not run on the board
```

## What is not known

Whether the controller's registers alone are enough, or the PCIe link must
also be trained again (the firmware's `pciex4_reset` setting, or its
reset and rescal lines `resets = <&rescal>, <&bridge>`, which are not
regions). A read of the controller's link-status register, once it is a
region, settles the first; the rest is for the driver and a later item.
The IOMMU's and RP1's DMA offsets (`dma-ranges`: bus 0x10_0000_0000 is
CPU 0) are as 0102 left them, the driver's.

## Done when

- spec 10.3's table and the board's part have the controller, 0x1000120000
  and 0x9310 bytes, Device-nGnRnE in the boot map's block that holds it
  (block 64, which holds the IOMMUs, 0x1000000000), and in a space's
  root table too, with a changelog entry giving the evidence above
- `tests/virt/pi5` opens it and its edges, as `rp1` does, and
  `tools/test.sh`, `--compiled`, and `--virt` are green
- run through `tools/pi5-run`: a read of the controller's status, whose
  value goes in the Log, and, if the window then answers after the
  firmware's state is as it is, RP1's chip ID read through it; if it does
  not, the Log says what the next step is and 0102's note that the window
  "holds while the firmware leaves the link set up" is corrected in the
  spec

## Log

- 2026-10-24: opened from 0110's reads of RP1. Next: the table and the
  board's part, as 0105 did for the HVS.
- 2026-10-24: done. Spec 10.3's table, changelog, `pi5-aarch64.ll` (8
  devices) and `tests/virt/pi5/pcie` made; `tools/test.sh`, `--compiled`
  and `--virt` (aarch64) green. Board read (`tmp/0113/pcie.l0`, 2 GB Pi 5):
  MISC_REVISION 0x406C = 0x500, MISC_PCIE_CTRL 0x4064 = 4,
  MISC_PCIE_STATUS 0x4068 = 0x3E0B0 (port, DL active, PHY link up, by the
  2711 bit layout: the link is up), 0x400C = 0x80000000, 0x4010 = 0,
  0x4070 = 0x3FF00000, 0x4080 = 0x4084 = 0x1C. So RP1 still reads
  0xDEADDEAD with the link up: the failing step is the outbound window or
  RP1's BAR1. The spec's "holds while the firmware leaves the link set up"
  is corrected. Next, for the driver and not this item: read RP1's config
  space through the controller's index/data registers (offsets are the
  2711's, to verify), and find BAR1 and the window.
