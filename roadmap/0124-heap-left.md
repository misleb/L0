# 0124: how much of its heap a program has left

Kind: language
Status: done, changelog "A program can ask how much of its heap is left";
not run on macOS, a Pi 5, or riscv64's half of `--virt`
Needs: none

## Why

L0S's `probes/memory/REQUEST-heap-left.md`: its kernel records every page
it gives a process in its own heap, and when processes take enough pages
the heap runs out before the frames do, and the kernel stops with `heap
exhausted`, taking the board with it. `frame_free_count` lets it refuse a
page when frames run out, but nothing tells it how much of its heap is
left, which only the runtime knows. Reproduced by L0S's
`test_frames_run_out` with a 96 MB kernel heap; L0S's roadmap 0001 (the
Pi 5 boots reliably) is blocked on it.

What could not be written: a kernel that refuses a process another page
while its heap could not record it.

## Done when

- the checklist in the `l0-bootstrap` skill, with the seed refreshed: a
  new `l0_` function and builtin
- spec 6.19 and its row in section 6's table, 9.2's host without a heap
  of its own, 10.3's declares, the host function, and how the runtime
  counts; changelog "A program can ask how much of its heap is left"
- `l0rt.ll` counts the bytes on its free lists; `freestanding.ll` counts
  the bytes in its free blocks; `host-libc.ll` gives -3
- tests: arity and type in `check_errors`; on a board and as a process,
  that the count falls as a program makes values and rises as it frees
  them; on the host, -3

## Log

- 2026-10-26: opened from L0S's request. Next: spec, changelog, runtime,
  compiler.
- 2026-10-26: done. Spec 6.19, its table row, 9.2, and 10.3; changelog;
  `l0rt.ll`'s `@free_bytes` and `l0_heap_left`, `freestanding.ll`'s
  `@heap_free` and `l0_host_heap_left`, `host-libc.ll`'s -3; the checker
  and emitter; `check_errors`, `bundle_prelude`, and `emit_tail`
  re-blessed; `tests/virt/heap_left` and `tests/io/heap_absent`.
  `tools/test.sh` 65, `--compiled` 158, `--virt` on aarch64 190 green;
  seed refreshed, and it reproduces itself. Freeing a million cells
  raised the count by 23,991,776 of their 24,000,000 bytes, the rest
  the runtime's own list of blocks to free. Not run: macOS, a Pi 5,
  riscv64's half of `--virt` (no qemu-system-riscv64 here).
