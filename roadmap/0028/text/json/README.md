# json, over an array of bytes

Validates and pretty-prints JSON from standard input as
`python3 -m json.tool --indent 2` does:

```
tools/l0 build json.l0 main.l0 -o json
./json < doc.json         # pretty-printed on stdout, exit 0
./json < bad.json         # stdin:LINE:COL: error: MESSAGE on stderr, nothing on stdout, exit 1
tools/l0 test json.l0 json_test.l0
```

## Files

- `json.l0`: reading, checking, printing, error positions (395 lines)
- `main.l0`: the entry point (21 lines)
- `json_test.l0`: 25 tests
- `testdata/sample.json` (0014's) and `sample.expected`, written by
  `python3 -m json.tool --indent 2`, not by this program
- `differ.py`: runs this and `json.tool` on 41 edge cases and lists every
  disagreement

## How it works

The input is read into an `(array int)` that starts at 64 K elements and
doubles when full, and is parsed by index: every parser function takes the
array, its length, and a position, and returns `(Ok next)` or `(Bad at
message)`.

**Nothing is built from the input.** There is no tree, no string, and no
output list. The same walk runs twice: first with handle -1, which checks the
whole document and writes nothing, then with handle 1, which writes the
output as it goes. So an invalid document writes nothing, even when its
error is at the last byte, and the only memory beyond the input array is the
parser's stack. (0014 could have walked its list twice as well; what the
array changes is 8 bytes a byte instead of 24 at best, and a position that
is an int, so an error's line and column are found without a second list.)

Strings are re-escaped straight from the input: `\uXXXX` escapes are written
per code unit in lower case, so surrogate pairs and lone surrogates pass
through as json.tool prints them. Raw UTF-8 is decoded, strictly (overlong
forms, surrogates, and values above U+10FFFF are errors), and written as
`\uXXXX`, astral code points as surrogate pairs. DEL is `\u007f`, `\/` is
`/`, as json.tool does.

## Status: done

- `tools/l0 test`: 25 of 25 pass, under the reference-count check: scalars,
  nesting, every escape, raw UTF-8 of 2 to 4 bytes, surrogates, numbers,
  twelve kinds of error with their positions, nothing written on error, input
  growth past 64 K, 100,000 levels of nesting (checked only; printing them
  would be 10 GB of indentation), the golden file, and a round trip over 300
  random documents: printing the printed text gives it back.
- The 11.5 MB document from 0014's `gen_big.py 100000` is printed
  **byte-identical** to `python3 -m json.tool --indent 2` (with its default
  `ensure_ascii`), and so is the 23 MB one from `gen_big.py 200000`.
- `L0_RC_CHECK=1` on the 11.5 MB document: nothing live at exit.
- `L0_ARRAY_STATS=1`: **0 copies**, 28,180,143 updates in place (12 million
  bytes stored, 16 million copied while doubling).

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

Second of two runs (`../measure.sh`). 0014's json was rebuilt with today's
compiler and measured the same way. Its README's figures, 1.9 s and 873 MB,
predate the faster compiler and release at last use.

| input | json | 0014 (list + tree) | `python3 -m json.tool --indent 2` |
|---|---|---|---|
| 1.1 MB (`gen_big.py 10000`) | 0.04 s, 33 MB | 0.07 s, 45 MB | 0.12 s, 22 MB |
| 5.7 MB (50,000) | 0.19 s, 129 MB | 0.35 s, 220 MB | 0.33 s, 61 MB |
| **11.5 MB (100,000)** | **0.38 s, 257 MB** | 0.68 s, 439 MB | 0.56 s, 111 MB |
| same, error at its last byte | 0.23 s, 257 MB | 0.33 s, 439 MB | |
| 23 MB (200,000) | 0.73 s, 513 MB | 1.35 s, 883 MB | 1.11 s, 210 MB |

Build: 0.45 s (0014's: 0.56 s).

**Memory is all input**: about 22 bytes per input byte at every size, which
is 0.58 of 0014's and 2.3 times Python's. None of it is parsing. Reading
the input alone peaks at 257 MB at 10 MB (`limits/01-input-into-array.l0`),
because the last doubling allocates 2^24 elements (134 MB) while the 67 MB
array it copies is still live, and the smaller arrays before it are still
resident. An array of exactly the input's length would be 8 bytes a byte,
89 MB measured here, but nothing tells the program the length first. So holding
bytes in an array, read the only way a program can read them, costs what a
list did. That is limit 01, and the case for 0026.
