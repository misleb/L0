# 0110: the checks 0098 left for a Pi 5, run on one

Kind: program
Status: active
Needs: 0108

## Why

0098, 0102, 0103, and 0105 are done "with no run on a board". 0098's first
run (2026-10-24, a 2 GB Pi 5, by TFTP) settled the EL2 entry, the debug
UART's region and byte writes, the firmware honouring `config.txt`,
`kernel_address`, and `device_tree_address`, and the power-off call being
reached. The product of this item is each remaining check run, and for each
that fails the smallest program that shows it, as a limit to report.

## The checks

From 0098's Log, 0102, 0103, and 0105, in the order of what the next needs:

- `/memory` ranges through `l0_board_map_ram`; only the 2 GB model has
  been seen: 4, 8, and 16 GB need a board this host does not have
- the UART's interrupt, GIC IDs 152 and 153, and the GIC at all
- user mode and interrupts on the Cortex-A76
- the arguments the firmware appends to `cmdline.txt`
- standard input from `initramfs input.bin`
- BL31's pages inside the first gigabyte block
- PSCI `SYSTEM_OFF` rather than the firmware halting (the log shows
  `Halt: power_off: 0`; say which it was)
- the RP1 region (0102), reading something it can name, such as the chip ID
  the firmware prints, `0x20001927`
- `frame_sync` and DMA, which are not coherent (0103)
- the HVS and `iommu4` regions (0105), and whether the firmware's display is
  still scanning out

## Done when

- each check has a program under `tmp/0110/` or, if worth keeping, a test
  in `tests/virt/pi5/`, and a Log line: passed, or failed with the output
- each failure is confirmed with `tools/l0check` where it is a language
  limit, and becomes a language item in the queue; a failure of the board's
  hardware or firmware is recorded as that
- 0098's, 0102's, 0103's, and 0105's lines in `INDEX.md` say which checks
  were run, instead of "no run on a board"

## Log

- 2026-10-24: opened after 0098's first run. Next: 0108, so each check is a
  command rather than a session.
- 2026-10-24: 0108 and 0109 are done. Run through `tools/pi5-run`, each
  with a power-cycle, and each output compared with its `.out`:
  `tests/virt/pi5/rp1.l0` printed `0 0 0 0 -3 -3` and `hvs.l0` printed
  `0 0 0 0 -3 -3 -3 -3`, both as expected. So the RP1 window (0102) and the
  HVS and IOMMU regions (0105) open and refuse as the spec's tables say. That
  is only region opening: nothing was read from RP1, the HVS, or an IOMMU.
  Next, in order of risk: the checks that read nothing risky (boot arguments,
  standard input, `/memory`'s range, the clock), then a read of RP1 and the
  HVS, then the GIC and interrupts, user mode, and `frame_sync`.
- 2026-10-24: `tmp/0110/basics.l0`, with `first base=0x09000000 a:b` as
  arguments and `hello` on standard input, on the board: the clock was sane
  (`clock ok`) and standard input arrived by `initramfs input.bin
  0x10000000`, returned reversed as `olleh`. The firmware gave 17 arguments
  of its own, before the program's three, where the spec has them after
  (0112). `(frame_free_count)` was 260,627.
- 2026-10-24: `tmp/0110/frames.l0` took every frame: 260,628, from
  0x1D8000 up to 0x3FBFF000, which I took for a fault, calling the board
  16 GB (0111, opened and dropped the same night). It was wrong: the boot
  log's `total-size: 16Gbit` is 2 GB, and a copy of the runtime under
  `tmp/` that printed each range `l0_board_map_ram` was given showed the
  firmware's two, `0` to `0x3FC00000` and `0x40000000` to `0x80000000`, which
  are all of a 2 GB board's RAM. The default heap (768 MB) and stack
  (256 MB) are the second range, so the pool is the first, as spec 10.3
  says it is with default sizes. The runtime read `/memory` right.
- 2026-10-24: `tests/virt/user_mode.l0`, `frame_sync.l0`, and
  `interrupts.l0` on the board, built with `--heap-mb 16 --stack-mb 16`,
  and with `tmp/0110/pi5board.l0` in place of `tests/virt/board/virt-
  aarch64.l0`: the Pi's UART at 0x107D001000, its interrupt 153, a no-device
  page, RAM at 0x40000000, the GIC's distributor, and the virt board's
  aarch64 instruction encodings. Each ran to its end and printed its `.out`
  exactly, but for the UART's interrupt number, 153 for QEMU's 33, as spec
  10.3's table gives it, and the line `l0: exit status 70` after a runtime
  error, which spec 10.3 says the Pi writes since its status reaches no
  host. So on a Cortex-A76 with the GIC-400: user mode (spaces, frames,
  mapped pages, device pages, and a thread run to a call, an unknown
  instruction, a missing page, and a page it may not run, with the same
  ESR values QEMU gave), `frame_sync` in all three directions, the virtual
  timer's interrupt at its deadline and not before, and the debug UART's
  transmit interrupt, raised, taken as 153, cleared, and ended; and ending
  the timer's twice is the error. Not shown by these: which of GIC IDs 152
  and 153 the silicon used, since the host reports either as 153.
  `frame_dma` was not run: its device is QEMU's.
- 2026-10-24: RP1, read for the first time. `tmp/0110/rp1id.l0` read
  0x1F00000000 and 0x1F00000004, where I guessed RP1's SYSINFO CHIP_ID and
  PLATFORM to be, and got `deaddead` twice; the firmware's log gives the
  chip ID as 0x20001927. That guess was mine, so `tmp/0110/rp1usb.l0` read
  what 0102's Log named instead: each USB controller's first word and
  GSNPSID at 0xC120, as 32-bit reads over 64 KB regions. All four were
  `deaddead`. No read faulted or hung. So the window answers but holds no
  RP1: the PCIe controller's outbound window and RP1's BAR1 are not set as
  the image runs, or are elsewhere, and the controller's registers, at
  0x1000120000, are no region, so no program can find out or set them
  (0113). 0102's plan, that `pciex4_reset=0` leaves the window answering,
  is shown wrong as far as it goes: it did not. The HVS's registers were
  not read; `deaddead` there would say less, and the HVS wants RP1's
  display path settled first.
- 2026-10-25: 0112 done: with `l0 card`'s marker, `basics.l0` on the board
  gave 3 arguments, the program's, where it gave 20.
- Checked: region opening for RP1 and the HVS and IOMMUs; arguments (0112,
  fixed); standard input; the clock; `/memory` and the frame pool; user mode;
  `frame_sync`; the GIC and the timer and UART interrupts; on the 2 GB
  model; a read of RP1 (failed, 0113). Left: a read from the HVS, `frame_sync`'s effect on a
  device's DMA (0103's coherence, which no test of QEMU's can show), the
  system timer's four interrupts, BL31's pages, whether SYSTEM_OFF or the
  firmware halted, and the 4, 8, and 16 GB models, which need a board this
  host does not have. The Pi's board file for these tests is in
  `tmp/0110/pi5board.l0`; it belongs in `tests/virt/board/` if they are to
  be run again.
