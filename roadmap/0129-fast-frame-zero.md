# 0129: `frame_new` zeroes at memory bandwidth

Kind: language
Status: queued
Needs: nothing

## Why

L0S's request 1 (its `build/l0-requests.md`, on a Pi 5, 2026-10-29):
8,192 `(frame_new)` calls take 22.4 ms, 2.75 us a 4 KB frame, about
1.5 GB/s, against 0.05 us a page for `space_map`. A compositor at 4K
allocates buffers of 8,000 to 13,000 pages, 22 to 35 ms of `frame_new`
alone, while every CPU's system calls wait on CPU 0. L0S now keeps a pool
of frames zeroed while idle to hide it.

The cause is here: `l0_host_frame_new` zeroes with `@zero_page`'s
`llvm.memset` (`runtime/bare/board.ll`), and the freestanding `memset`
it lowers to (`runtime/freestanding.ll`) stores one byte at a time.

What could not be written: a kernel that gives a process a large buffer
without stalling every CPU for tens of milliseconds.

Asked: zeroing at memory bandwidth on aarch64 and riscv64. If a cache
clean is needed for DMA, spec 6.13 says so, since `frame_sync` already
covers it.

## Done when

- the checklist in the `l0-bootstrap` skill
- a frame and a table page are zeroed in wide stores, or `dc zva` on
  aarch64 (boot.ll already sets the SCTLR bit that allows it at EL0's
  side; check it is allowed at EL1 and read DCZID_EL0 for the block
  size); `memset`, `memcpy`, and `memmove` in `freestanding.ll` copy a
  word at a time once aligned, since every program on a board uses them
- spec 6.13 says whether a new frame needs `frame_sync` before a device
  reads it, as it does now
- measured: 8,192 frames on `--virt`, before and after, in the Log; on a
  Pi 5 if one is at hand

## Log

- 2026-10-29: opened from L0S's request 1. Next: measure on `--virt`,
  then the runtime.
