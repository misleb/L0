# 0100: a region can be closed

Kind: language
Status: done, changelog "A region can be closed"; passed on Linux arm64
Needs: nothing

## Why

L0S, the kernel's own project, asked for it in
`probes/region-close/REQUEST-region-close.md` there. `l0rt.ll` keeps the
open regions in a table of 64 and never frees a slot, so the 65th open
gives -5 however few are in use. L0S's compositor opens two regions a
window, over shared buffers it gives up when the window closes, so it can
open 30 windows over its life, and resizing, which needs new buffers and
so new regions, cannot be built. Nothing outside `l0rt.ll` can free a
slot. What it would write (its `want.l0`):

```
(def drop_buffer ((r int)) int
  (region_close r))
```

```
want.l0:15:3: error: unknown function region_close
```

## The plan

- spec 6.12: `region_close`, 64 open at once, the lowest free number;
  section 8's `not a region` for a close too; 10.3: `@l0_region_close`,
  the host's `l0_host_region_close`, and call 13, `unregion`
- runtime: a free slot is a length of 0; `l0_region_open` takes the
  lowest, and hands the host's mapping back before giving -5 for a full
  table; every host defines `l0_host_region_close`, a process's making
  call 13
- compiler: the builtin, arity 1, int to int
- `lib/io.l0`: `close_device`
- `tests/virt/user/kernel.l0` answers 13 by unmapping the window pages,
  and takes them back when they are the last given; the IR harness kernels
  answer it as a call they do not know
- tests: a close, a reopen, and opening past 64 at once and past 64 over
  a life, on the board and as processes; closing twice; and under
  kernel.l0 more opens and closes than its window has pages
- the seed refreshed, since `lib/io.l0` uses the builtin

## Done when

- the checklist in the `l0-bootstrap` skill
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green

## Log

- 2026-10-21: opened from L0S's request, and started. Spec, changelog,
  compiler, runtime, hosts, and `close_device` written.
- 2026-10-21: implemented as planned. `unregion` fails with kernel.l0
  ignoring call 13 (`refused: -5`, its 512-page window spent) and passes
  answering it. `region_close` first read the serial port at width 4,
  a fault on the riscv64 board's 16550; it reads the clock now. Suites
  green: 65, 150, `--virt` 313 passed, 88 skipped; Linux arm64 65 and
  150. Seed refreshed, since `lib/io.l0` uses the builtin; L0S's
  `want.l0` checks with `tools/l0`. Next: tell L0S, whose side is
  answering call 13 and closing in `wm`.
