# 0033: The library reads into bytes, and the text programs use it

Kind: tooling
Status: proposed, needs 0032
Needs: 0032

## Why

[0026](0026-packed-bytes.md)'s prototype moved 0028's json, sort, and
wordfreq onto packed bytes (`0026/bench/stage2/`) by reading with the builtin
directly and checking `read_from` afterward for a failure. `lib/io.l0`
should do that once, returning a result type, as `next_line` does for lines.
It cannot be written in 0032 itself: `tools/l0` builds programs and the
library with the seed, which knows `bytes` only after 0032's seed refresh,
and `lib/prelude.l0` cannot use the type at all while stage 0 runs it.

## Done when

- `lib/io.l0` has a documented function that reads the rest of an `IoFile`
  into `bytes`, with a result type that carries a read failure, tested in
  `tests/unit/io_test.l0`, and `tests/io/libdoc/index.txt` regenerated and
  its diff read
- the shipped `l0-code` skill says when to hold input as `bytes`
- 0028's json, sort, and wordfreq moved onto it, with their READMEs'
  numbers re-measured, and `0026/bench/` deleted

## Log

- 2026-09-29: opened from 0026's finding.
