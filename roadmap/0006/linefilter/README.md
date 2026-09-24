# linefilter: keep the lines that contain "ERROR"

**Status: partly written.** `linefilter.l0` checks, runs, and matches
`grep ERROR` byte for byte on every input tried (the committed test and
generated inputs from 1 MB to 300 MB). It does **not** do the part that makes
this task interesting: run in memory proportional to one line. It also cannot
write a match before end of input, and its substring is a constant because
there are no command-line arguments.

| File | What it is |
| --- | --- |
| `linefilter.l0` | the program |
| `test/input.txt`, `test/expected.txt` | edge cases (no final newline, empty line, near misses); expected output is from `grep` |
| `measure.sh [MB ...]` | peak memory against input size; checks output against `grep` |
| `timing.sh` | when output appears when input arrives one line per second |

## Memory: proportional to the input, at about 53 bytes per input byte

`measure.sh 1 10 100 300`, on macOS with 48 GB of RAM. Lines average 38
bytes. "Peak footprint" includes pages macOS compressed under memory pressure.
"Max RSS" does not, which is why it undercounts at 300 MB.

| input | input bytes | output bytes | max RSS | peak footprint | footprint / input byte | time (s) | matches grep |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 MB | 1048594 | 106720 | 54.8 MB | 54.5 MB | 54.5 | 0.39 | yes |
| 10 MB | 10485768 | 1067108 | 536.8 MB | 536.7 MB | 53.7 | 0.17 | yes |
| 100 MB | 104857626 | 10671356 | 5336.7 MB | 5338.9 MB | 53.4 | 1.65 | yes |
| 300 MB | 314572836 | 32014022 | 9824.1 MB | 16042.5 MB | 53.5 | 8.55 | yes |

Memory would be flat if it were proportional to one line. Instead it grows
linearly with the input, at 53.5 bytes of footprint per input byte. At that
rate a 1 GB log needs about 54 GB, more than this machine has, so I did not
run it. The cost splits into three parts, and each has its own limit
program in `../limits/`:

- about 17 bytes per input byte before `main` runs, because the host builds
  all of stdin as a list first ([limit 01](../limits/01-input-read-whole.l0))
- about 32 bytes per input byte for the per-line lists (the reversed line,
  then its `rev`), all of it garbage that is never freed
  ([limit 02](../limits/02-no-reclamation.l0))
- about 32 bytes per output byte for the output accumulator and its final
  `rev`, which must exist in full before anything is written
  ([limit 03](../limits/03-output-held-until-exit.l0))

## Timing: nothing is written until end of input

`timing.sh` writes three lines one second apart and closes stdin at t+3:

```
linefilter:
  t+ 0.00s  stdin  b'ERROR one\n'
  t+ 1.01s  stdin  b'ok\n'
  t+ 2.00s  stdin  b'ERROR two\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'ERROR one\nERROR two\n'
  t+ 3.01s  exit   b'0'
first output byte at t+3.01s.

grep --line-buffered ERROR (reference):
  t+ 0.00s  stdin  b'ERROR one\n'
  t+ 0.01s  stdout b'ERROR one\n'
  t+ 1.01s  stdin  b'ok\n'
  t+ 2.01s  stdin  b'ERROR two\n'
  t+ 2.01s  stdout b'ERROR two\n'
  t+ 3.00s  eof    b''
  t+ 3.00s  exit   b'0'
first output byte at t+0.01s.
```

So `tail -f app.log | linefilter` would never print anything.
[Limit 04](../limits/04-no-output-before-eof.l0) is the same wall.

The code that should have been possible is
[hypothetical/01](../hypothetical/01-input-read-whole.l0), and, with the
substring taken from the command line,
[hypothetical/05](../hypothetical/05-no-command-line.l0).
