# 0104: a board program sizes its heap and stack, or brings its own layout

Kind: language
Status: done, changelog "A board program sizes its heap and stack, or
brings its own layout"
Needs: nothing

## Why

L0S, the kernel's own project, asked for it in its proposal "Kernel-Sized
Board Layouts", and it is 0097's item 2, left for an item of its own. A
board's layout, `runtime/board/BOARD.ld`, fixes the program's heap and
stack, and the frame pool is only the windows between them. A kernel is an
ordinary board program, so it gets a program's layout: on the aarch64 virt
board at 2 GB, a heap of 1,024 MB and a stack of 256 MB, and 765 MB of
frames for every process. L0S measured its full demo, 65 processes: a
kernel heap of 20.5 MB at its peak, 12.3 MB of it its copy of the
initramfs, a stack under 8 KB, and about 30 MB of frames in use.

No L0 can ask for more frames, since the pool is fixed before `main`
runs. Whatever a kernel does, this reports at most 195,933 on that board:

```
(def main () int
  (do (write_line (int_to_string (frame_free_count))) 0))
```

The user asked too, for a microkernel: keep the static layouts for
testing generic board programs, and let a program such as a kernel define
its own layout, or change a template's with command-line options.

## The plan

L0S's items 1 to 3; item 4, the RAM under the user range, waits for an
item of its own.

- spec 10.3: a board's layout is a template that `l0 build` fills with a
  heap size and a stack size, today's by default, from `--heap-mb` and
  `--stack-mb`; the heap's start and the stack's top stay where they are,
  so neither depends on standard input's size. `--layout FILE` replaces the
  template: what such a script must define and where, and what the
  driver checks. The options are only for board targets.
- spec 10.3: the frame windows become what the boot map reaches, a
  board's fixed ranges, less everything below the image's end, the heap,
  the stack, the device tree, and standard input's bytes until read. With
  the default sizes the pool is today's.
- runtime: the board parts give their reach as windows; `board.ll` cuts
  the image, heap, and stack as holes beside the device tree and input.
  The templates take `__l0_heap_size` and `__l0_stack_size`.
- tools: `tools/l0` takes the three options for `build`, `run`, `link`,
  and `test` on `virt` and `pi5`, refuses them elsewhere, checks the sizes
  against the manifest's room, and writes the layout it links with: the
  sizes, the template or the file, and the checks. Each manifest gives
  `T_HEAP_MB`, `T_STACK_MB`, and `T_ROOM_MB`.
- tests: `tools/test.sh` reads a `tests/virt` program's `<stem>.layout`,
  options for its build; a program with a small heap and stack sees the
  pool grow, one with too little heap runs out of it, sizes that do not fit
  are refused, and a layout file links and runs.

## Done when

- the checklist in the `l0-bootstrap` skill; no compiler change, so no
  seed refresh
- `tools/test.sh --virt` green on both CPUs

## Log

- 2026-10-22: opened from L0S's proposal and the user's request, and
  started.
- 2026-10-22: implemented as planned. The boards' windows are now their
  reach (aarch64 virt one, riscv64 and the Pi two), and `board.ll` cuts
  five holes. With the default sizes the aarch64 pool is 195,942 frames,
  today's less nothing; with 64 and 16 MB it passes 450,000 on both CPUs
  (`tests/virt/layout_sized`). lld reports a failed `ASSERT` twice, which
  `layout_overlap.refused` records as it is. Suites green: 65, 152,
  `--virt` 332 passed, 88 skipped. No compiler change, so no seed
  refresh. Next: tell L0S it can build its kernel with `--heap-mb` and
  `--stack-mb`; L0S's item 4 and a heap grown from the pool are items of
  their own when taken up.
