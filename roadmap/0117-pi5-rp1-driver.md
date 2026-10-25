# 0117: a first RP1 driver, as a process on the Pi 5

Kind: program
Status: dropped
Needs: 0115

## Why

0114 made RP1 answer from a bare program and 0115 ran a kernel with
driver processes. A driver for an RP1 device, run as a process, is the
first program of the kind the goal names, and where its limits show.

## Done when

- a process, given the controller's and RP1's regions by the kernel, sets
  the PCIe controller up as `lib/AGENTS.md` says and drives one RP1
  device by polling: first, reading each USB controller's identity
  (xHCI CAPLENGTH and HCIVERSION, DWC3 GSNPSID at 0xC120) as 0102 asked,
  then a device with visible effect, such as a GPIO line or RP1's UART
- each limit it hits is written here and, if it is the language's, opened
  as an item

## Log

- 2026-10-25: dropped, the same day it was opened. The user's microkernel,
  in another project, is bringing up RP1's USB by polling, with the
  installed toolchain and `lib/AGENTS.md`'s notes; that is this item's
  program, written where it is used. What it cannot write comes back here
  as requests, each to become an item.
