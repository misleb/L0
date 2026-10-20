# 0097: the virt boards' frames come from all the RAM the layout leaves

Kind: language
Status: done, changelog "The virt boards' frames come from all the RAM
the layout leaves"; passed on Linux arm64
Needs: nothing

## Why

L0S, the kernel's own project, asked for it in
`l0-request-board-memory.md` there. The virt boards' pool of frames is
fixed by the layout at 384 MB, 0x98000000 to 0xB0000000 on aarch64 and
0x100000000 to 0x118000000 on riscv64, and capped at 98,304 pages by
`board.ll`'s bookkeeping. Every process of L0S's kernel lives in frames,
so the pool runs dry while most of the board sits idle: on aarch64 the
127.5 MB after the image, the 127 MB around the device tree, and the input
window are never used, and the input window's pages, whose bytes the
program has copied into its heap, can never be given back.

A kernel also cannot learn how much is left, so it cannot refuse a spawn
the pool cannot hold (`roadmap/0097/why.l0`):

```
(def can_spawn ((pages int)) bool
  (ge (frame_free_count) pages))
```

```
$ tools/l0check lib/io.l0 roadmap/0097/why.l0
roadmap/0097/why.l0:4:7: error: unknown function frame_free_count
```

## The plan

L0S's items 1, 3, and 5. Item 2, the heap and stack sized by the program
or a heap that grows from the pool, is left for an item of its own; item
4, standard input kept as frames, waits for a program that needs it.

- spec 10.3: the pool is the RAM the device tree's `/memory` nodes
  describe, within the windows the board's layout leaves, less the
  device tree and standard input's bytes; those join once standard input
  has been read to its end. Where a board's standard input is, which the
  spec has never said. No cap on the number of frames.
- spec 6.13: `frame_free_count`; 9.2's absence; 10.3's calls
- compiler: the name, its arity, its call and `declare`
- runtime: `l0_frame_free_count` over `l0_host_frame_free_count`; the
  board's host builds the pool at boot in pieces, sizes its bookkeeping
  from it, and keeps a count; the other hosts give -3
- tests: `check_errors`; `tests/io/user_absent`; on the board, the pool
  drained and filled again, more than 98,304 frames, and the input's
  pages joining

## Done when

- the checklist in the `l0-bootstrap` skill, with the seed refreshed
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green

## Log

- 2026-10-20: opened from L0S's request, items 1, 3, and 5, and started.
- 2026-10-20: implemented as planned. The board parts give windows
  (`l0_board_window_count`, `_start`, `_end`) in place of a pool's two
  ends; `board.ll` reads `/memory`, cuts the windows into at most 32
  pieces, keeps `page_state` in the pool, and counts `pool_left`. The pool
  drains at 195,933 frames on aarch64 at 2 GB, about 765 MB, up from
  98,304; `tests/virt/unit/pool_test` drains and refills it on both CPUs,
  and `tests/virt/pool_input` sees 9,000 bytes of input join as 3 pages.
  Suites green: 65, 149, `--virt` 293 passed, 88 skipped; Linux arm64 65
  and 149; seed refreshed, fixpoint holds. Next: tell L0S; item 2, the
  heap grown from the pool, is its own item when taken up.
