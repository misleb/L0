# 0111: the Pi 5's frame pool is one gigabyte on a 16 GB board

Kind: language
Status: dropped; the finding was wrong, the board is 2 GB
Needs: nothing

## Why

Opened from 0110's run of `tmp/0110/frames.l0`, which took every frame on
the Pi 5 and found 260,628, from 0x1D8000 up to 0x3FBFF000, about 1 GB.
I took the board for 16 GB, since the first run's notes said so, and
read that as a pool a sixteenth of the board's RAM.

## Why it was dropped

The board is 2 GB. Its boot log says `Initialising SDRAM ... size-gbit:16`,
which is 16 gigabits, and `boardrev b04171` is a 2 GB model. A copy of the
runtime under `tmp/`, which printed each range `l0_board_map_ram` was
called with, showed the firmware's `/memory` as `0` to `0x3FC00000` and
`0x40000000` to `0x80000000`: all of the RAM there is, and exactly the
board's 2 GB with the GPU's top of the first gigabyte left out. The
default heap, 768 MB, and stack, 256 MB, take the second range, so the
pool is the first gigabyte, as spec 10.3 gives it with default sizes.

Nothing in the runtime, the spec, or the tools was wrong, and nothing was
changed for this item. The record of the error is kept, as the roadmap
keeps a dropped item, since the way to it was a note's unchecked figure.
Roadmap 0098's and 0110's notes now say 2 GB.

## Log

- 2026-10-24: opened, run, and dropped the same night.
