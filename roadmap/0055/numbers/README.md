# 0055 numbers and bits

Three programs, written from the shipped guide, skill, spec, `l0 doc`, and
`l0 examples` only. All their tests pass under `l0 test` (with its
reference-count check). Each program's outputs match its reference exactly.
Machine: Apple M4 Pro, 48 GB.

## What was read

`roadmap/0055-programs-round-three.md`, `lib/AGENTS.md`,
`lib/skills/l0-code/SKILL.md`, the spec that `l0 spec --path` names
(`spec/L0.md`: sections 1 to 9 and 11 in full, and 10.1 and 10.3 in part),
the `l0 doc` index, `l0 doc int_prefix` and `l0 doc file_next_line`,
`lib/examples.l0` in full and the start of `lib/examples_test.l0`, and
`l0 help`. Nothing under `compiler/`, `runtime/`, `stage0/`, or `tests/`.

## The programs

| program | files | build |
| --- | --- | --- |
| `hash/sums FILE`: CRC-32 and SHA-256, printed as `crc32`, `cksum -o 3`, and `shasum -a 256` print them | `hash/bits.l0` `hash/sums.l0` `hash/main.l0`, tests `hash/sums_test.l0` (21) | `l0 build hash/bits.l0 hash/sums.l0 hash/main.l0 -o hash/sums` |
| `calc/calc [--int64]`: exact rationals, `+ - * /`, unary minus, parentheses, lowest terms and 20 places (rounded half away from zero) | `calc/rat.l0` `calc/big.l0` `calc/num.l0` `calc/calc.l0` `calc/main.l0`, tests `calc/calc_test.l0` (18) `calc/big_test.l0` (17) | `l0 build calc/rat.l0 calc/big.l0 calc/num.l0 calc/calc.l0 calc/main.l0 -o calc/calc` |
| `sieve/sieve bits\|flags N`: the number of primes up to N and the largest, from a bitset or from a flag per number | `sieve/bitset.l0` `sieve/flags.l0` `sieve/report.l0` `sieve/main.l0`, tests `sieve/sieve_test.l0` (10) | `l0 build sieve/bitset.l0 sieve/flags.l0 sieve/report.l0 sieve/main.l0 -o sieve/sieve` |

References are in `ref/`: `hash_vectors.py` (test vectors), `make_data.py`
(writes `data/big.bin`, 100 MB, seed 55), `pysums.py` (CRC and SHA in pure
Python), `libsums.py` (zlib and hashlib), `pycalc.py` (the same calculator
over `Fraction`, and with `--int64` the same 64-bit refusals), `gen_exprs.py`
(writes `data/exprs.txt`, 100,000 random expressions), and `pysieve.py`.

`L0_ARRAY_STATS=1` reports 0 array copies for `sums` and for both sieves.

## Results

Times are wall-clock, peak memory is the maximum resident set size from
`/usr/bin/time -l`, and sizes are `wc -l` of the program's files, tests
excluded and comments included.

| task | L0 | time | peak memory | reference | time | peak memory |
| --- | --- | --- | --- | --- | --- | --- |
| CRC-32 + SHA-256, 100 MB | `sums`, 408 lines | **10.24 s** | 2.8 MB | `cksum -o 3` + `shasum -a 256` | 0.22 + 0.21 s | 1.2 / 7.1 MB |
| | | | | Python zlib + hashlib (C) | 0.12 s | 21.6 MB |
| | | | | pure Python (10 MB, ×10) | 16.7 s → ~167 s | 146 MB |
| calculator, 100,000 lines, `--int64` | `calc --int64` | **0.77 s** | 1.7 MB | `pycalc.py --int64` | 2.69 s | 62 MB |
| calculator, 100,000 lines, exact | `calc`, 676 lines | **19.75 s** | 1.7 MB | `pycalc.py` (Fraction) | 3.56 s | 65 MB |
| sieve to 10^8, bitset | `sieve bits`, 87 lines (+29 shared) | **1.08 s** | 14.8 MB | Python bytearray, slice assignment | 0.42 s | 295 MB |
| sieve to 10^8, flag per number | `sieve flags`, 38 lines | **1.64 s** | 802 MB | Python bytearray, one index at a time | 3.06 s | 115 MB |

Correctness:

- `sums` agrees with `crc32`, `cksum -o 3`, and `shasum -a 256` on
  `data/big.bin`: `2c090c22`, `738790434 100000000`, and
  `553bcc1a…fde79824`. It also matches 14 vectors from Python, which cover
  every padding boundary (55, 56, 63, 64, 65, 119, 120, and 128 bytes) and
  all 256 byte values.
- `calc` is byte-identical to `pycalc.py` on all 100,000 lines, every
  result exact (up to 185 characters). With `--int64` it differs from
  `pycalc.py --int64` on 97 lines, each one an overflow it reports in an
  intermediate whose reduced answer fits (limit 3). Wherever it answers, it
  is right.
- `sieve`: 5761455 primes up to 100000000, the last 99999989, both ways and
  in Python. The bitset and flag versions agree for every N up to 400.

Where the time goes in `sums` (`limits/phases_main.l0`): reading 100 MB in
64-byte blocks takes 0.29 s, adding CRC-32 makes it 1.78 s, and SHA-256 alone
takes 8.22 s. So 95% of the run is arithmetic standing in for bitwise
operations. `limits/02-xor-cost.l0`, at 100M steps each, prices one
operation:

| step | ns |
| --- | --- |
| loop with `add` and `mod 2^32` | 1.46 |
| plus one `div` and one `mod` by 256 | 2.58 |
| plus a table-driven `xor32` (bits.l0) | 13.94 |
| plus a bit-at-a-time `xor32`, no table | 136.73 |

In the sieve, crossing off takes 835 ms (about 3.5 ns per mark, roughly
2.4·10^8 marks), and counting 5.7M primes with a 64K popcount table takes
4 ms. The bitset beats the flag array despite emulating its bits: the
flags are 8 bytes each, 800 MB of memory traffic.

## Limits, ranked by cost

Each limit has a smallest program under `limits/`, confirmed with
`l0 check`, and the code that would have been written is under
`hypothetical/`.

1. **No bitwise operations: and, or, xor, not, shifts, popcount**
   (`limits/01-no-bitwise.l0`: `error: unknown function bit_xor`). This hit
   two of the three programs. The workaround is `hash/bits.l0` (137 lines):
   two 64K-entry byte tables threaded through every call, words split with
   `div` and `mod` by 256, rotations as `div`/`mod`/`mul` by powers of two,
   and the CRC register held as four separate bytes so its inner step needs
   no division. Cost: `sums` takes 10.2 s where `cksum` and `shasum` take
   0.43 s together, and 9.95 s of that is arithmetic standing in for bit
   operations (one emulated xor32 is 12.5 ns, against the loop's own
   1.5 ns). The bitset holds 63 bits a word, not 64, and a bit costs two
   divisions, a remainder, and a lookup. Would be written as
   `hypothetical/sums.l0` and `hypothetical/bitset.l0`. With the builtins,
   `bits.l0` disappears, and SHA-256 drops to about 25 lines of plain code.
   I estimate (not measured) about a second for 100 MB.
2. **No big integers** (`limits/06-no-big-integers.l0`:
   `error: integer literal does not fit in 64 bits`). Over 64-bit
   rationals, the calculator cannot answer 47,596 of 100,000 ordinary lines
   (integers up to 999, nested four deep). It reports each one rather than
   wrapping. The workaround is `calc/big.l0` (261 lines: base-10^9 limbs in
   lists, decimal long division) plus `calc/num.l0` (75 lines: a number
   that is small while it fits and big when it does not). With it the
   calculator is exact and matches Python on every line, but takes 19.75 s
   against Python's 3.56 s and its own 0.77 s with `--int64`. The division
   is naive, a decimal digit at a time, so part of that is the workaround's
   algorithm and not only L0. Would be written as `hypothetical/rat.l0`.
3. **Arithmetic wraps silently, with nothing to detect it**
   (`limits/05-wrapping-arithmetic.l0` type checks and prints `0` for
   2^32 · 2^32 and `-9223372036854775808` for (2^63 − 1) + 1). The exact
   calculator needs about 45 of `rat.l0`'s 174 lines for checked `add` and
   `mul`, `Option` threading, and an overflow-free 10·r mod d. With no
   widening multiply, Knuth's addition still overflows in an intermediate
   on 97 of the 100,000 lines whose answer fits.
4. **No compact array that can be changed** (`limits/04-no-mutable-bytes.l0`:
   `unknown function bytes_set`, `unknown function bytes_new`). `bytes`
   cannot be updated, and every array element is a 64-bit word. So the
   byte-per-flag sieve the task asks for cannot be written: the nearest,
   an `(array bool)`, takes 802 MB where Python's bytearray takes 115 MB.
   Making n zero bytes also needs a list of n first (24 bytes each).
5. **No hexadecimal literals** (`limits/03-no-hex-literal.l0`:
   `invalid character in integer literal`). Every published CRC and SHA
   constant is in hex. The workaround parses a string of hex words at
   startup (`hex_words` in `bits.l0`) so the constants can be checked
   against FIPS 180-4 by eye. Decimal (3988292384) would have worked too.
   The cost is legibility, not time.
6. **No top-level values** (`limits/07-no-top-level-values.l0`:
   `each parameter is (name type)`). A table computed once (the CRC table,
   SHA's K, the byte tables) is built at startup and passed to every
   function that reads it. `sums.l0` carries it through nine functions.
   Passing is free (read-only parameters), so the cost is in signatures,
   not time.
7. (Already known from 0041.) No function values: `num.l0` passes the
   operation as an int code (0 to 3) and dispatches with `if`.

Not limits: decimal printing to 20 places needed no floating point (30 lines
of integer long division in `rat.l0`). Writing hex output (`push_hex`) and
`abs` took a few lines each. Reading a file 64 bytes at a time with
`file_read_byte` costs 0.29 s per 100 MB in 2.8 MB, which is fine.

## In the docs

- `l0 run` builds "to a temporary file" (`l0 help`), and neither
  `lib/AGENTS.md` nor the skill says where. In this repository nothing may
  be written outside `$HOME/projects`, so I used `l0 build -o` throughout.
  If the file goes to `$TMPDIR`, the commands that `lib/AGENTS.md` and the
  skill recommend break that rule.
- When a declaration fails to parse (a bad literal, a malformed `def`),
  the checker drops it, and every later use is reported again as
  `unknown function poly` or `unknown variable crc_table`. The second error
  is misleading (seen in limits 03, 06, and 07).
- The skill says `digits` "is the only way to print a number". True, but
  the library reads hex (`hex_val`) and has nothing to write it, so every
  program that prints a digest writes its own.
- `l0 check` on a file with no `main` prints `ok`. The guide and skill
  always show it with `main.l0` and do not say a library file alone can be
  checked, though that is useful.
- The prompt said the spec is at `lib/L0.md`; `l0 spec --path` prints
  `spec/L0.md`.
- Spec 6.9 defines `hash` with `xor` and a logical `>>` on unsigned 64-bit
  words: operations L0 programs cannot write. Not wrong, but it shows that
  the spec itself needs them.

## Files

`hash/`, `calc/`, `sieve/`: the programs and their tests, as above.
`limits/01-no-bitwise.l0`, `02-xor-cost.l0` (measurement),
`03-no-hex-literal.l0`, `04-no-mutable-bytes.l0`,
`05-wrapping-arithmetic.l0`, `06-no-big-integers.l0`,
`07-no-top-level-values.l0`, `phases_main.l0` and `sieve_phases_main.l0`
(phase timers). `hypothetical/sums.l0`, `bitset.l0`, `rat.l0`. `ref/`
and `data/` as above. `data/big.bin` is 100 MB, and `ref/make_data.py`
writes it again.
