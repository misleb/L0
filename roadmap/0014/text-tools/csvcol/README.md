# csvcol

`csvcol FILE N` prints column N, counted from 1, of each record of a CSV file,
one line per record.

```
$ printf 'name,quote\nAnn,"said ""hi"", then left"\n' > a.csv
$ csvcol a.csv 2
quote
said "hi", then left
```

The format is RFC 4180's. Quoted fields may hold commas, newlines, and `""`
for a quote. A carriage return outside quotes is dropped, so CRLF files work.
A quote inside an unquoted field is data. A record with fewer than N fields
prints an empty line.

Errors go to stderr, prefixed `csvcol:`:

| case | message | exit |
|---|---|---|
| wrong number of arguments | `usage: csvcol FILE N` | 2 |
| N not a positive integer, or over 18 digits | `bad column number "abc": it is not a positive decimal integer` | 2 |
| missing file | `FILE: no such file` | 1 |
| unreadable file | `FILE: permission denied` | 1 |
| a directory | `FILE: input or output failed` | 1 |
| unclosed quote | `FILE: record 2: a quoted field is not closed before the end of the file` | 1 |
| text after a closing quote | `FILE: record 1: a closing quote is followed by something other than a comma or the end of the record` | 1 |

Output is streamed, so records before a malformed one have already been
printed when the error is reported, and so has the start of the bad record's
field, if it is column N.

## Files

- `csvcol.l0`: the parser, as a pure step function `(step state byte n)`,
  plus the in-memory driver `extract` and the argument parser
- `main.l0`: the entry point, which drives `step` from the file
- `csvcol_test.l0`: 18 tests, including a property test that quoting and
  extracting any 300 random byte strings gives them back
- `gen.py`: a CSV generator full of commas, quotes, newlines, and CRLF
- `reference.py`: the same extraction using Python's `csv` module

## Status: done

- `l0 test`: 18 of 18 pass.
- The output is byte-identical to `reference.py` on a 14.5 MB file
  (`gen.py 200000 8`) for columns 1, 5, 8, and 9 (past the end).
- Every error case above was run by hand, with the exit status shown.
- `L0_RC_CHECK=1` reports nothing live on the 14.5 MB file or on the error
  paths.

## Measurements

On the 14.5 MB file, column 5, using `programs/measure.sh`:

| | time | peak RSS |
|---|---|---|
| csvcol (step function, testable) | 1.07 s | 1.6 MB |
| the same parser written directly (`limits/02-...-direct.l0`) | 0.27 s | 1.5 MB |
| Python `csv` module | 0.19 s | |

Memory is constant, whatever the file size.

## Workarounds, named

- **The parser is turned inside out so that it can be tested (limit 02).**
  L0 cannot pass a byte source as an argument, so a parser that reads its own
  bytes can read a file or a string, not both. I wrote it as a pure
  `(state, byte) -> state` function that each source drives. It costs a
  factor of 4 in time, from allocating a `Csv` state and a `Mode` per byte,
  and some clarity, since each mode's code sits in a separate function taking
  the same five arguments. The direct version is 51 lines and the step
  version 82, both with comments. The alternative, parsing temporary files in the tests, would
  keep the fast parser but put file plumbing in every test.
