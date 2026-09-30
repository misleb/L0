# 0033: The library reads into bytes, and the text programs use it

Kind: tooling
Status: done, changelog "The library reads a whole input into bytes, and no
language change for it"; Linux runs owed
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
- 2026-09-30: done, broadened to every library file and the examples.
  - `lib/io.l0`: `IoBytes` (`IoBytes b` or `IoReadFailed code`),
    `read_input`, `file_read_all`, `file_write_bytes`. Tested in
    `tests/unit/io_test.l0` (memory handles, after a line, empty, wrong
    direction, after close, a write range, a range error, a 5,000-byte
    random round trip), and in `tests/io/read_input` and
    `read_input_failure` (standard input a directory: exit 3, the words of
    -5). `tests/io/libdoc/index.txt` regenerated; its diff is only the new
    entries and the header.
  - `lib/test.l0`: `compare_file` reads with `file_read_all` and reports a
    failed read; its private `read_all` is gone, and the framework's
    shadowing test defines `first_diff` instead.
  - `lib/examples.l0`: arrays (`most_common_byte`) and bytes
    (`count_newlines`, `lines_of_input`, `write_first_line`), with tests.
  - Both l0-code skills: the shipped one says to read a whole input with
    `read_input` into bytes and when; the repository one lists bytes among
    what stage 0 rejects.
  - 0028's json, sort, and wordfreq taken from the prototype and moved onto
    the library; tests 24, 10, and 15, all pass under the reference-count
    check. Output byte-identical to `json.tool` (11.5 and 23 MB),
    `reference.py` and `LC_ALL=C sort` (10 and 20 MB), and wordfreq's
    `reference.py` (both inputs, and the top 10). No array copies. Median
    of three: json 11.5 MB 0.20 s, 13.6 MB; sort 10 MB 0.08 s, 17.6 MB;
    wordfreq wide 0.28 s, 25.1 MB, narrow 0.14 s, 4.0 MB, the prototype's
    figures. READMEs rewritten with the array versions kept as a column.
  - `lib/prelude.l0` unchanged: stage 0 runs it. Bytes comparison, written
    in sort and in wordfreq in different shapes, left out of the library.
  - `0026/bench/` deleted; 0026 points to git history for it.
