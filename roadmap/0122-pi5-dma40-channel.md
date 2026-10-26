# 0122: the Raspberry Pi 5's dma40 channel 6 is a region, with its interrupt

Kind: language
Status: done, changelog "The Raspberry Pi 5's dma40 channel 6 is a region,
with its interrupt"; no run on a board
Needs: 0120

## Why

L0S's `probes/audio/REQUEST-pi5-dma40.md`. Its `hdmi-audio` driver
would feed HDMI0's MAI by DMA, as Linux's `vc4_hdmi` does; `open_device`
refuses `dma40`, since section 10.3 lists no DMA controller, and the CPU
feeding the FIFO underruns behind any other process's slice. L0S's
`probes/audio/want.l0` opens the channel and gets `DeviceFailed`.

## The plan

- spec 10.3: the Pi's region table gains channel 6, 0x1000010600, 0x100;
  its interrupt table gains 118, the GIC's SPI 86
- `runtime/board/pi5-aarch64.ll`: the device, in block 64, and 118 in
  `l0_board_irq_exists`
- `tests/virt/pi5/dma`: opens it, ranges beside it that are none, and
  enables 118 and the numbers either side
- no emulator: checked by building and linking; a first run is the user's

## Done when

- the checklist in the `l0-bootstrap` skill
- the pi5 target builds; `tools/test.sh --virt` green

## Log

- 2026-10-26: opened from L0S's request; channel 6 alone, the request's
  first choice. Implemented.
