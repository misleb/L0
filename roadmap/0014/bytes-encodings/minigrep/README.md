# minigrep

`minigrep PATTERN FILE...` prints each line of each file that PATTERN
matches, as `FILE:LINE`. A pattern is literal bytes, `.` for any byte, `x*`
for zero or more of a byte or `.`, `^` at the start and `$` at the end as
anchors. Elsewhere `^` and `$` are literal, and so is a `*` with nothing
before it, as in a POSIX basic regular expression. `**` means `*`, as in GNU
grep. Exit status is 0 if any line matched, 1 if none did, and 2 on an error
(usage, a file that cannot be opened or read), as with grep. After an error
it goes on to the remaining files.

```sh
export L0_COMPILER=$PWD/build/l0c-native L0_RUNTIME=$PWD/build/l0rt.o
tools/l0 build programs/minigrep/minigrep.l0 programs/minigrep/minigrep_main.l0 -o /tmp/minigrep
tools/l0 test programs/minigrep/minigrep.l0 programs/minigrep/minigrep_test.l0
programs/minigrep/compare.sh 1000
programs/minigrep/bench.sh 20
```

## Status: done

- **Tests:** 20 of 20 pass, and also pass under `L0_RC_CHECK=1`. They cover
  literals, both anchors, anchors used as literals, `.`, `*` with
  backtracking, a leading `*`, high bytes, parsing, and whole files: the
  name prefix, a last line with no newline, blank lines, and a missing
  file.
- **Differential test** (`compare.sh`): 1,000 random patterns over `a b . *`
  with random anchors, against 300 random lines. 77 patterns contain `**`,
  which macOS's BSD grep rejects as invalid, so they were skipped. The
  output for the other 923 is identical to `LC_ALL=C grep`. Exit statuses
  check out as 0, 1, and 2 (missing file) and 2 (usage).
- **Throughput** on a 20 MB text file of 500,708 lines, best of three,
  Apple M4 Pro. Peak memory is 1.6 MB throughout, since it streams:

  | pattern | minigrep | grep |
  | --- | --- | --- |
  | `kappa lambda mu` | 1.08 s | 0.10 s |
  | `^alpha.*mu$` | 0.49 s | 0.11 s |
  | `eta.*iota.*kappa` | 2.28 s | 0.46 s |
  | `zzz` | 1.05 s | 0.07 s |

  That is 5 to 15 times slower than grep, and about 20 MB/s where there is
  no match.

## What L0 made costly

**Bytes are cons cells (limit 02).** A line has to be built as a list, one
24-byte cell per byte, and then reversed into order. Counting lines that way
takes 0.43 s on this file, against 0.06 s reading the same bytes without
building anything (`programs/limits/02-bytes-as-lists.l0`). So about 0.4 s
of every row above is spent making lines, before any matching. That is why
the anchored pattern, which fails on the first byte of most lines, still
takes 0.49 s. The rest of the `zzz` time (about 0.6 s, or 30 ns for each of
the 20 million starting positions) is the matcher walking lists. Each step
is a runtime call for `head` or `tail` and reference-count traffic, where a
byte string could be indexed. No workaround was attempted: the program is
correct, and a faster one needs a different representation of bytes, which
is a language change.

**Testing through files (limit 05).** `grep_path` writes to a handle, so the
tests that check its output go through `/tmp` files. That is 26 lines of
helpers, the same kind as base64's.

**No generic list functions (limit 04):** `rev_toks`, and `length_toks` in
the tests.

## Design notes

The matcher is Kernighan and Pike's backtracking matcher from *The Practice
of Programming*, over lists. Its cost is linear for a pattern without `*`,
and grows as a power of the line length with the number of `*`s. Lists
suit this matcher: "the rest of the line" is just the tail. The standard
`file_read_line` cannot tell a failed read from the end of the file, so
`read_line_h` is written here to report a failed read as an error, with exit
status 2.
