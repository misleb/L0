# 0102: the Raspberry Pi 5's RP1 is a region

Kind: language
Status: queued
Needs: 0101

## Why

L0S's `probes/usb/REQUEST-pcie-rp1-cache.md`, its second ask. On the Pi 5
both USB controllers are DWC3s in host mode on RP1, the southbridge behind
PCIe, at 0x1F00200000 and 0x1F00300000 in RP1's peripheral window,
0x1F00000000 to 0x1F00400000. Spec 10.3 says the Pi's "RP1, behind PCIe, is
none", so an xHCI driver cannot reach them. The window holds only while
the firmware leaves the PCIe x4 link to RP1 set up, which it does when
`config.txt` says `pciex4_reset=0`, and `l0 card`'s does not.

## The plan

- spec 10.3: the Pi's table gains RP1's peripherals, 0x1F00000000 and
  0x400000 bytes; `l0 card`'s `config.txt` is said to keep RP1 set up
- `runtime/board/pi5-aarch64.ll`: the device, and the boot map's block
  that holds it, Device-nGnRnE, in a space's root table too
- `l0 card`: `pciex4_reset=0`
- RP1's DMA offset (bus 0x10_0000_0000 is CPU 0) stays the driver's to
  add, so `frame_address` stays the CPU's address; the spec says so
- no emulator: checked by building and linking, and a first run on a board
  is the user's, as 0098's was

## Done when

- the checklist in the `l0-bootstrap` skill
- the pi5 target builds; `tools/test.sh --virt` green, since the boot code
  is shared

## Log

- 2026-10-21: opened from L0S's request; queued after 0101.
