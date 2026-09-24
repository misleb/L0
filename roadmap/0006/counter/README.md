# counter: a running count of every word, reported per line

**Status: partly written.** `counter.l0` checks, runs, and matches an awk
reference byte for byte on every input tried (the committed test and generated
inputs from 1 MB to 100 MB). For each input line it writes the running count
of each word on that line, for example `a b a` gives `a=1 b=1 a=2`. It does
**not** behave as a long-running loop should:

- **Its state is a dozen table entries, but its memory grows with the input,
  at about 200 bytes per input byte.**
- **Every report appears at once, after end of input.** Someone typing lines
  sees nothing until they press Ctrl-D.
- **It survives a large input only because `clang -O2` turns its tail calls
  into jumps.** At `-O0` it dies of stack exhaustion on 10 MB.

| File | What it is |
| --- | --- |
| `counter.l0` | the program |
| `test/input.txt`, `test/expected.txt` | edge cases (empty line, double and leading spaces, no final newline); expected output is from `awk` |
| `measure.sh [MB ...]` | peak memory against input size; checks output against `awk` |
| `timing.sh` | when output appears when input arrives one line per second |
| `tailcalls.sh` | the same IR built at -O0, -O1, -O2 |

## Memory: about 200 bytes per input byte, for a 14-word table

`measure.sh 1 10 100`. The input is generated with `genlines.sh MB noid`, so
the whole input uses 14 distinct words, and the table never holds more than
14 entries (about 1 KB).

| input | input bytes | lines | output bytes | max RSS | peak footprint | footprint / input byte | time (s) | matches awk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 MB | 1048593 | 28188 | 1930483 | 193.9 MB | 193.6 MB | 193.6 | 0.94 | yes |
| 10 MB | 10485788 | 281876 | 20995284 | 2004.8 MB | 2005.4 MB | 200.5 | 0.81 | yes |
| 100 MB | 104857613 | 2818753 | 226864156 | 9766.2 MB | 20800.2 MB | 208.0 | 11.56 | yes |

The 100 MB run reached a 20.8 GB footprint. About 17 bytes per input byte are
stdin as a list ([limit 01](../limits/01-input-read-whole.l0)). About 69 are
the output, which is 2.16 times the input and is held twice, as the
accumulator and its `rev` ([limit 03](../limits/03-output-held-until-exit.l0)).
The remaining ~120 are garbage that is never freed
([limit 02](../limits/02-no-reclamation.l0)). Per word, that garbage is the
word's reversed and forward lists, `bump`'s copy of the table up to the
word's entry, and the `digits` list. A collector alone would remove only the
~120, leaving about 86 bytes per input byte, or 8.6 GB for this 100 MB input.
Streaming I/O alone would leave the garbage. Both are needed.

## Timing: every report appears after end of input

`timing.sh` types three lines one second apart:

```
counter:
  t+ 0.00s  stdin  b'a b a\n'
  t+ 1.01s  stdin  b'b\n'
  t+ 2.00s  stdin  b'c a\n'
  t+ 3.00s  eof    b''
  t+ 3.00s  stdout b'a=1 b=1 a=2\nb=2\nc=1 a=3\n'
  t+ 3.00s  exit   b'0'
first output byte at t+3.00s.

awk, flushing per line (reference):
  t+ 0.00s  stdin  b'a b a\n'
  t+ 0.01s  stdout b'a=1 b=1 a=2\n'
  t+ 1.00s  stdin  b'b\n'
  t+ 1.01s  stdout b'b=2\n'
  t+ 2.00s  stdin  b'c a\n'
  t+ 2.00s  stdout b'c=1 a=3\n'
  t+ 3.00s  eof    b''
  t+ 3.00s  exit   b'0'
first output byte at t+0.01s.
```

## Tail calls: the loop survives only because of an unspecified optimization

`tailcalls.sh` builds the IR from `tools/l0 emit` at three optimization
levels:

| input | -O0 | -O1 | -O2 |
| --- | --- | --- | --- |
| 1 MB | ok | ok | ok |
| 10 MB | exit 70: l0: runtime error: stack exhausted | ok | ok |

Every loop in L0 is recursion, and section 8 leaves tail-call elimination
unspecified. So whether a long-running L0 loop runs indefinitely, or dies
once its input passes some size, is decided by the optimizer, not by the
program or the spec. `tools/l0 build` happens to use `-O2`.

The code that should have been possible is
[hypothetical/02](../hypothetical/02-no-reclamation.l0). Its `bump` is this
file's `bump`, unchanged.
