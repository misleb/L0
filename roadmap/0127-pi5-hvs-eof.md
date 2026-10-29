# 0127: the Raspberry Pi 5's display interrupt controller, disp_intr, is a region, with its interrupt

Kind: language
Status: done, changelog "The Raspberry Pi 5's display interrupt
controller, disp_intr, is a region, with its interrupt"; aarch64
`--virt` green; not run on a Pi 5 or riscv64's half of `--virt`
Needs: 0105

## Why

L0S's `probes/display/REQUEST-pi5-hvs-eof.md`. Its `hvs` driver polls
the channel's `DL` register for up to 50 ms after every restack, since
on SCALER6 a channel's end of frame is a line of `disp_intr`, not an HVS
register. `hvs eof` on a Pi 5 got "no device there" from
`open_device(0x107C502000, 0x30)` and -3 from `interrupt_enable 129`.
L0S's roadmap 0005, and 0006 after it, wait on it.

## The plan

- spec 10.3: the Pi's region table gains `disp_intr`, 0x107C502000,
  0x30; its interrupt table gains 129, the GIC's SPI 97; a paragraph on
  its registers and lines
- `runtime/board/pi5-aarch64.ll`: the device, in block 65, and 129 in
  `l0_board_irq_exists`
- `tests/virt/pi5/hvs_eof`: opens it, ranges beside it that are none,
  and enables 129 and the numbers either side
- no emulator: checked by building and linking; a first run is the user's

## Done when

- the checklist in the `l0-bootstrap` skill

## Log

- 2026-10-29: opened from L0S's request, which the L0S session
  "Coordinating parallel roadmap items" handed over; done the same day.
  Pixel valve 0's interrupt, the request's alternative, is not given.
