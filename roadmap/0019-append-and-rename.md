# 0019: Append to a file, and replace one whole

Kind: language
Status: queued
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
