# 0019: Append to a file, and replace one whole

Kind: language
Status: done, changelog "Appending to a file, and replacing one in a single step"
Needs: 0018

## Why

From [0014](0014-programs-round-two.md), `0014/data-structures/limits/02-no-file-update.l0`,
re-checked in the main tree: appending one line to a 200,000-line file reads
and rewrites all of it, since `open_write` empties the file and there is no
append. The worker measured 20 ms at 10,000 lines and 235 ms at 200,000,
against 12 ms for `echo >>` at every size. Because `open_write` empties the
file before anything is written and nothing can replace a file in one step,
a crash while kvstore saves loses the store: crash safety is impossible.
Checker output for the hypothetical: `error: unknown function open_append`.

Spec 6.3 is also silent on what `open_read` does on a directory. On macOS it
succeeds and the first read returns -5. This item settles it.

## Done when

The l0-bootstrap checklist, plus kvstore's append-only store written with the
new builtins as a test.

## Log

- 2026-09-24: opened from 0014.
- 2026-09-24: done. `open_append` and `rename`, with `open_appending` and
  `rename_file` in `lib/io.l0`; opening a directory for reading is now -5.
  `remove` from the worker's hypothetical was left out, since the log store
  needs no cleanup. `tests/unit/kvlog.l0` is the store, and its test and the
  new cases in `tests/unit/io_test.l0` are green on macOS and Linux. Adding a
  line is now 7 ms at 200,000 lines, against 266 ms rewriting. Fixed on the
  way: `tools/test.sh` never passed a `tests/unit/*.extra` file's sources,
  since it read the file after changing directory. Next is 0020.
