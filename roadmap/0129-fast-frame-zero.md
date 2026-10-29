# 0129: `frame_new` zeroes at memory bandwidth

Kind: language
Status: done, changelog "A frame is zeroed a cache block at a time, by dc
zva on aarch64"; measured on a Pi 5; not run on riscv64's half of `--virt`
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
- 2026-10-29: the cause was not what the request supposed. At `-O2`
  LLVM vectorizes `memset`'s byte loop into 32-byte `stp q0, q0` stores,
  so pages were already zeroed 32 bytes at a time; what stores cannot
  avoid is reading each line of a page not in the cache, every new
  frame's, before overwriting it. Now `@zero_page` calls the CPU's
  `l0_arch_zero_page`: `dc zva` on aarch64, a block at a time
  (`DCZID_EL0`'s size; stores if its DZP is set), which zeroes in the
  cache with no read, as Linux's `clear_page` does; stores on riscv64.
  `memset` stores words from the first aligned address, checked against
  libc for every offset 0 to 15 and length 0 to 40. HCR_EL2 traps no
  `dc zva` (only RW is set), and SCTLR_EL1 has the data cache on. Spec
  6.13 says a new frame's zeros reach a non-coherent device only after
  `frame_sync` 1 or 3; 10.3 says how a page is zeroed; changelog "A frame
  is zeroed a cache block at a time, by dc zva on aarch64".
  Measured on QEMU's aarch64 board, 8,192 `frame_new`: about 990 ns each
  before, about 1,000 ns with word stores, about 1,790 ns with `dc zva`,
  which QEMU emulates by a helper call with no cache to miss; QEMU says
  nothing of the board. Next: the same program on a Pi 5, which needs
  the user to power-cycle it.
- 2026-10-29: measured on a Pi 5 (2 GB), `tools/pi5-run`, in ns a
  `frame_new`, with `dc zva` and with stores alone (`dc zva` forced off
  for the second):

  | Frames | `dc zva` | stores |
  | --- | --- | --- |
  | 256 fresh, 1 MB | 243 | 281 |
  | the same 256 again, in the cache | 101 | 137 |
  | 8,192 fresh, 32 MB | 2,669 | 2,709 |

  So zeroing runs at 17 GB/s, 40 GB/s from the cache, until the caches
  fill, and then at what writing the lines back to DRAM costs, about 1.5
  GB/s, by stores or `dc zva` alike: L0S's 8,192 frames, 2,736 ns each
  in the first run here against its 2,750, are 32 MB, past every cache.
  No instruction avoids that, since a frame's zeros reach memory in the
  end. `dc zva` is kept: 14 to 26% faster while frames fit in the
  caches, and no slower past them. Left open: 1.5 GB/s is below what
  Linux is reported to write on this board, which may be the clocks the
  firmware leaves the CPU and memory at with no cpufreq; that is a board
  item if a program needs it, and L0S's pool of frames zeroed while idle
  is the answer for a kernel that needs many at once.
