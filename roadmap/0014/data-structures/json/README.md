# json: validate and pretty-print JSON

**Status: done.**

```sh
tools/l0 build programs/json/json.l0 programs/json/main.l0 -o json
./json < doc.json            # pretty-printed on stdout, exit 0
./json < bad.json            # stdin:LINE:COL: error: MESSAGE on stderr, exit 1
tools/l0 test programs/json/json.l0 programs/json/json_test.l0
```

Objects, arrays, strings with every escape (including `\u` escapes and
surrogate pairs, decoded to UTF-8 and re-escaped on output), 64-bit integers,
`true`, `false`, and `null`. Fractions and exponents are rejected with "only
integers are supported", not truncated. An integer that does not fit in 64
bits is an error, caught before it wraps: digits accumulate as a negative
number so that the most negative int is representable. Output is two spaces
per level, with `[]` and `{}` kept on one line.

## Files

- `json.l0`: the parser, the printer, and error positions (374 lines)
- `main.l0`: the entry point (24 lines)
- `json_test.l0`: 27 tests
- `testdata/sample.json`, `sample.expected`: the golden file
- `gen_big.py`: writes a large document for timing

## Results

- `tools/l0 test`: 27 passed, 0 failed. The tests cover scalars, integer
  limits, every escape, the error messages and positions, 100,000 levels of
  nesting, a golden file, and a round-trip property over 300 random values:
  printing, parsing, and printing again gives the same text.
- Every test also passes under `L0_RC_CHECK` with no runtime report
  (`programs/rc_check_tests.sh`, below).
- Mutation check: swapping two bytes of the UTF-8 encoder fails 2 tests.
- An 11.5 MB document (100,000 records, from `gen_big.py`) is printed
  **byte-identical** to `python3 -m json.tool --indent 2 --no-ensure-ascii`.

| input | time | peak memory |
| --- | --- | --- |
| 11.5 MB, valid | 1.9 s (Python: 0.47 s) | 873 MB |
| same, error at its last byte | 0.83 s | 463 MB |

## What L0 cost here

- **The memory is limit 04**: bytes are cons cells. The input list alone is
  24 bytes per byte (276 MB); with the tree and the 17 MB output list, it
  peaks at 76 times the input. A 100 MB document would need about 7.6 GB.
- **Limit 05**: the whole-input `main` always exits 0. A validator has to
  exit nonzero on bad input, so `main` streams and reads stdin itself, with a
  4-line `read_stdin`.
- **Limit 03**: no type parameters. `rev_json` and `rev_members` repeat the
  prelude's `rev`. Strings need their own result type `PS`, plus
  `string_value` and two match arms that only move an error from `PS` to
  `PJ`. The tests need four generator types: `Gen`, `GenList`, `GenMembers`,
  and `GenStr`.
- **Limit 06**: no wildcard arm. The round-trip test compares rendered text
  rather than trees, because `json_eq` over 6 constructors is 36 arms.
- The prelude's `length` is not tail recursive, so the error position uses a
  tail-recursive `count` instead. `length` on the input would add about
  320 MB of stack at 10 MB.

One design choice avoided a cost rather than paying one. A parse error
carries the remaining input at the failure, not a position. The offset is
`count(input) - count(rest)`, computed once when the error is reported, so no
parser function threads a counter or returns one.
