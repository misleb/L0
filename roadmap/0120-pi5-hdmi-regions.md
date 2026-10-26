# 0120: the Raspberry Pi 5's HDMI0 mode set is regions

Kind: language
Status: done, changelog "The Raspberry Pi 5's HDMI0 mode set is regions";
no run on a board
Needs: nothing

## Why

L0S's `probes/display/REQUEST-pi5-hdmi-mode.md`. Its `hvs` driver keeps
the firmware's 1920x1080 on a 4K monitor; the firmware's `SET_TIMING` gets
4K but keeps the HVS channel's lists. HDMI0's controller, PHY, pixel valve
and DDC are not regions, so `open_device` refuses them.

## The plan

- spec 10.3: the Pi's table gains four rows
- `runtime/board/pi5-aarch64.ll`: the devices, all in block 65
- `tests/virt/pi5/hdmi`: opens them, and ranges beside them that are none
- no emulator: checked by building and linking; a first run is the user's

## Done when

- the checklist in the `l0-bootstrap` skill
- the pi5 target builds; `tools/test.sh --virt` green

## Log

- 2026-10-26: opened from L0S's request; addresses checked against the
  request's table (decimal conversions checked with printf); implemented.
  No compiler change, so no seed refresh. Suites green: 65, compiled 156,
  aarch64 `--virt` 180 passed, 46 skipped, `hdmi` among the Pi 5's builds.
  riscv64's half not run: no qemu-system-riscv64 here. Alongside, the
  tools now link bare images with `ld.lld` from PATH when `L0_VIRT_LD` is
  unset, before falling back to Docker.
