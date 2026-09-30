# json, over bytes

Validates and pretty-prints JSON from standard input as
`python3 -m json.tool --indent 2` does:

```
tools/l0 build json.l0 main.l0 -o json
./json < doc.json         # pretty-printed on stdout, exit 0
./json < bad.json         # stdin:LINE:COL: error: MESSAGE on stderr, nothing on stdout, exit 1
tools/l0 test json.l0 json_test.l0
```

## Files

- `json.l0`: checking, printing, error positions (360 lines)
- `main.l0`: the entry point, reading with `read_input` (21 lines)
- `json_test.l0`: 24 tests
- `testdata/sample.json` (0014's) and `sample.expected`, written by
  `python3 -m json.tool --indent 2`, not by this program
- `differ.py`: runs this and `json.tool` on 41 edge cases and lists every
  disagreement

## How it works

The input is read whole with `read_input` from `lib/io.l0`, as `bytes`, one
byte per byte, and is parsed by index: every parser function takes the
bytes, their length, and a position, and returns `(Ok next)` or `(Bad at
message)`. (Until 0033 it was read into an `(array int)` that doubled as it
filled; see Measurements.)

**Nothing is built from the input.** There is no tree, no string, and no
output list. The same walk runs twice: first with handle -1, which checks the
whole document and writes nothing, then with handle 1, which writes the
output as it goes. So an invalid document writes nothing, even when its
error is at the last byte, and the only memory beyond the input is the
parser's stack. (0014 could have walked its list twice as well; what bytes
change is one byte a byte instead of 24, and a position that is an int, so
an error's line and column are found without a second list.) Numbers go out
straight from the input with `write_bytes`.

Strings are re-escaped straight from the input: `\uXXXX` escapes are written
per code unit in lower case, so surrogate pairs and lone surrogates pass
through as json.tool prints them. Raw UTF-8 is decoded, strictly (overlong
forms, surrogates, and values above U+10FFFF are errors), and written as
`\uXXXX`, astral code points as surrogate pairs. DEL is `\u007f`, `\/` is
`/`, as json.tool does.

## Status: done

- `tools/l0 test`: 24 of 24 pass, under the reference-count check: scalars,
  nesting, every escape, raw UTF-8 of 2 to 4 bytes, surrogates, numbers,
  twelve kinds of error with their positions, nothing written on error, a
  long input, 100,000 levels of nesting (checked only; printing them
  would be 10 GB of indentation), the golden file, and a round trip over 300
  random documents: printing the printed text gives it back.
- The 11.5 MB document from 0014's `gen_big.py 100000` is printed
  **byte-identical** to `python3 -m json.tool --indent 2` (with its default
  `ensure_ascii`), and so is the 23 MB one from `gen_big.py 200000`.
- `L0_RC_CHECK=1` on the 11.5 MB document: nothing live at exit.
- It uses no arrays at all now; the array version made 28,180,143 updates
  in place, 16 million of them copying while doubling.

### Where the output differs from json.tool

`differ.py` finds exactly these, under a UTF-8 locale:

- **Numbers with a fraction or exponent** are printed as written; json.tool
  prints `repr(float(x))`: `1.50` as `1.5`, `1E5` as `100000.0`, `1e-3` as
  `0.001`, `0e0` as `0.0`, `1e400` as `Infinity`. L0 has no floating point
  (limit 03). Integers match, `-0` included, which both print as `0`.
- **Duplicate keys** are all printed; json.tool keeps one, at the first
  key's position with the last value: `{"a":1,"b":2,"a":3}` is
  `{"a": 3, "b": 2}`. Doing the same needs a table of keys per object. That
  is writable, and was not written.
- **`NaN`, `Infinity`, `-Infinity`** are rejected, as RFC 8259 requires;
  json.tool accepts them.
- json.tool **rejects** integers of more than 4,300 digits (Python's
  conversion limit) and nesting deeper than about 1,000 levels (its
  recursion limit). This program accepts both.
- Under the `C` or `C.UTF-8` locale, Python's stdin decodes invalid UTF-8
  with `surrogateescape`, so json.tool prints each bad byte as `\udcXX`. This
  program rejects invalid UTF-8, as json.tool does under a UTF-8 locale.

## Measurements

json over bytes (0033): median of three runs, `/usr/bin/time -l`, Apple
Silicon, macOS. The other columns are from the second of two runs
(`../measure.sh`) at 0028: json over an array, and 0014's json rebuilt with
the compiler of then. 0014's README's figures, 1.9 s and 873 MB, predate the
faster compiler and release at last use.

| input | json, bytes | json, array (0028) | 0014 (list + tree) | `python3 -m json.tool --indent 2` |
|---|---|---|---|---|
| 1.1 MB (`gen_big.py 10000`) | 0.02 s, 3.7 MB | 0.04 s, 33 MB | 0.07 s, 45 MB | 0.12 s, 22 MB |
| 5.7 MB (50,000) | 0.11 s, 8.1 MB | 0.19 s, 129 MB | 0.35 s, 220 MB | 0.33 s, 61 MB |
| **11.5 MB (100,000)** | **0.20 s, 13.6 MB** | 0.38 s, 257 MB | 0.68 s, 439 MB | 0.56 s, 111 MB |
| same, error at its last byte | 0.10 s, 13.5 MB | 0.23 s, 257 MB | 0.33 s, 439 MB | |
| 23 MB (200,000) | 0.40 s, 24.7 MB | 0.73 s, 513 MB | 1.35 s, 883 MB | 1.11 s, 210 MB |

**Memory is the input, once**: 1.1 to 1.2 bytes per input byte from 5.7 MB
up, against 22 for the array version, 38 for 0014's, and about 10 for
Python's. `read_input` reads into a buffer that doubles and is trimmed, and
the buffer is the bytes value, so only `realloc` ever holds two copies. The
array version peaked at 257 MB at 10 MB because the last doubling allocated
2^24 elements (134 MB) while the 67 MB array it copied was still live
(`limits/01-input-into-array.l0`, limit 01), which is what 0026 and 0032
answered. It also takes half the time, not profiled; it no longer reads one
byte per call or stores eight bytes for each.
