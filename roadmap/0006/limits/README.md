# Limits: the smallest program for each place L0 stopped

Each file is the smallest L0 program that shows one limit. Some limits are
about memory or timing rather than type errors. Those files check and run,
and their evidence is a measurement. The rest fail the checker. Exact checker
output for every file is in [`../check.txt`](../check.txt), produced by
`../check.sh`. The code that should have been possible for `NN` is
`../hypothetical/NN-*.l0`.

| # | Limit | Blocks | Evidence |
| --- | --- | --- | --- |
| 01 | stdin is read whole before `main` runs | linefilter, counter, (filecopy) | 17 bytes per input byte for a program that ignores its input |
| 02 | memory is never reclaimed | linefilter, counter | 16 bytes per cons cell ever made, live or not |
| 03 | output is held until `main` returns | linefilter, counter | 16 bytes per output byte, 32 with the `rev` idiom |
| 04 | no output before end of input | prompt, linefilter and counter in a pipeline | first byte appears only when stdin closes (`../prompt/README.md`) |
| 05 | no command-line arguments | filecopy, linefilter's substring | `l0 build`: `error: main must take one parameter of type (list int)` |
| 06 | no files | filecopy | `unknown function 'read_file'`, `unknown function 'write_file'` |
| 07 | no way to report failure | filecopy | `unknown function 'fail'`; 07b shows the only nonzero exit is a crash (70) |

## Memory measurements (`measure.sh`)

macOS, 48 GB of RAM. "Peak footprint" includes pages macOS compressed under
memory pressure, and "max RSS" does not. They agree until memory is tight, as
in the 10,000,000 row.

### 01-input-read-whole: `main` returns 0 without reading its input

| input | max RSS | peak footprint | footprint / input byte | time (s) | exit | output bytes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 MB | 18.5 MB | 18.1 MB | 18.1 | 0.58 | 0 | 2 |
| 10 MB | 173.5 MB | 173.2 MB | 17.3 | 0.02 | 0 | 2 |
| 100 MB | 1703.9 MB | 1704.4 MB | 17.0 | 0.25 | 0 | 2 |

This is a floor that no allocator can lower. The whole list is live when
`main` is entered, because `main`'s parameter refers to its first cell.

### 02-no-reclamation: N iterations, each builds and drops a 64-cell list

| N | max RSS | peak footprint | footprint / cell made | time (s) | exit | output bytes |
| --- | --- | --- | --- | --- | --- | --- |
| 1000 | 2.5 MB | 2.1 MB | 34.3 | 0.50 | 0 | 8 |
| 100000 | 99.2 MB | 98.8 MB | 16.2 | 0.03 | 0 | 10 |
| 1000000 | 978.3 MB | 978.4 MB | 16.0 | 0.28 | 0 | 11 |
| 10000000 | 8673.5 MB | 9773.9 MB | 16.0 | 2.91 | 0 | 12 |

Live data never exceeds one 64-cell list, about 1 KB. The last row uses
9.8 GB to hold it.

### 03-output-held-until-exit: N lines of `y\n` from a one-line input

| output | max RSS | peak footprint | footprint / output byte | time (s) | exit | output bytes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 MB | 17.5 MB | 17.2 MB | 17.2 | 0.54 | 0 | 1048576 |
| 10 MB | 161.5 MB | 161.3 MB | 16.1 | 0.03 | 0 | 10485760 |
| 100 MB | 1601.9 MB | 1602.3 MB | 16.0 | 0.35 | 0 | 104857600 |

## Checker results

```
$ tools/l0check lib/prelude.l0 programs/limits/06-no-files.l0
programs/limits/06-no-files.l0:10:4: error: unknown function 'read_file'
programs/limits/06-no-files.l0:13:4: error: unknown function 'write_file'

$ tools/l0check lib/prelude.l0 programs/limits/07-no-failure-report.l0
programs/limits/07-no-failure-report.l0:11:4: error: unknown function 'fail'

$ tools/l0check lib/prelude.l0 programs/limits/05-no-command-line.l0
ok: 2 files type check together          <- wrong; see ../README.md
$ tools/l0 build programs/limits/05-no-command-line.l0
error: main must take one parameter of type (list int)
```

07b checks and runs. Its exit status is 70, stdout is empty, and stderr is
`l0: runtime error: head of empty list`.
