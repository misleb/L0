# 0105: the Raspberry Pi 5's HVS and its IOMMU are regions

Kind: language
Status: done, changelog "The Raspberry Pi 5's HVS and its IOMMU are
regions"; no run on a board
Needs: nothing

## Why

L0S's `probes/display/REQUEST-pi5-hvs-iommu.md`. Its `hvs` driver composes
the Pi 5's screen with the BCM2712's HVS (SCALER6), which the firmware
leaves scanning HDMI0, writing display lists into the HVS's own memory and
mapping each client's scattered pages as one run through `iommu4`, the
IOMMU in front of the HVS. None of them is a region, so its probe,
`probes/display/want.l0`, opens nothing on a Pi 5, as on the host:

```
regions: 0
version: -1
channel 0: -1
```

The places, checked against the Raspberry Pi kernel's `rpi-6.12.y` device
tree (`bcm2712.dtsi`, `bcm2712-ds.dtsi`; `axi`'s ranges are the identity):
the HVS, `reg = <0x10 0x7c580000 0x1a000>`, with `iommus = <&iommu4>`
(commented out in `rpi-6.6.y`); `iommu4`, `reg = <0x10 0x5200 0x0 0x80>`;
`iommuc`, the cache it names, `reg = <0x10 0x5b00 0x0 0x80>`.

## The plan

- spec 10.3: the Pi's table gains the three; `l0 card`'s `config.txt` is
  said to force HDMI's hotplug
- `runtime/board/pi5-aarch64.ll`: the devices, and the boot map's block
  64, 0x1000000000, which holds the IOMMUs and nothing mapped before,
  Device-nGnRnE like block 65, which holds the HVS
- `l0 card`: `hdmi_force_hotplug=1`, and test.sh's check of it
- `tests/virt/pi5/hvs`: opens the three, and the ranges beside them that
  are none, reading nothing
- `disp_intr`, the HVS's end-of-frame interrupts, waits for its own request
- no emulator: checked by building and linking; a first run is the user's

## Done when

- the checklist in the `l0-bootstrap` skill
- the pi5 target builds; `tools/test.sh --virt` green, since the boot code
  is shared

## Log

- 2026-10-22: opened from L0S's request, addresses checked against the
  device tree; started.
- 2026-10-22: done. Spec, changelog, the board's part (block 64 and the
  three devices), `l0 card`'s `hdmi_force_hotplug=1` and test.sh's check
  of it, and `tests/virt/pi5/hvs`. No compiler change, so no seed
  refresh. Suites green: 65, 152, `--virt` 333 passed, 88 skipped, `hvs`
  among the Pi 5's builds. On a first run, beyond `hvs.out`: L0S's
  `probes/display/want.l0`, whose version word, 0x53 or 0x54, says the
  HVS is where the device tree says.
