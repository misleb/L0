# 0058: bitwise operations

Kind: language
Status: done, changelog "Bitwise operations"; passed on Linux arm64
Needs: 0057

## Why

[0055](0055-programs-round-three.md)'s numbers worker: one CRC-32 step, as
every CRC, hash, checksum, and bitset needs it, cannot be written.

```
(def crc_step ((table (array int)) (crc int) (b int)) int
  (bit_xor (array_get table (bit_and (bit_xor crc b) 255))
           (shr crc 8)))

(def main () int
  (crc_step (array_new 256 0) 4294967295 97))
```

```
$ tools/l0 check tmp/0055/numbers/limits/01-no-bitwise.l0
tmp/0055/numbers/limits/01-no-bitwise.l0:7:38: error: unknown function bit_xor
```

The workaround, 137 lines of 64K tables with `div` and `mod`, makes one xor
13.1 ns against 1.6 ns for the loop around it, and CRC-32 with SHA-256 of
100 MB 9.3 s against 0.43 s for `cksum` and `shasum`. The bitset sieve
holds 63 bits a word. 0028's grids found masks by `div` and `mod` 17 times
slower than flag arrays. Spec 6.9 defines `hash` with xor and a logical
shift, which no L0 program can write.

## Done when

- the spec names the operations (at least and, or, xor, and left and
  right shifts, logical and arithmetic), says what each does on every
  `int`, including shifts by a negative amount or by 64 or more, and the
  changelog says why each is in and what was left out (popcount, rotate)
- the names are checked against 0031's rule that a new builtin does not
  take over a program's function
- stage 0 is not extended; the compiled suite tests them under
  `tests/io/` with hand-written expectations
- `tmp/0055/numbers/hash/` rewritten with them, measured against the
  workaround, and kept as a test or an example if it earns its place
- the l0-bootstrap checklist

## Log

- 2026-10-06: queued by 0055, with the user's agreement.
- 2026-10-07: done.
  - spec 6.10: `bit_and`, `bit_or`, `bit_xor`, `bit_shl`, `bit_shr`
    (logical), and `bit_count`; a shift by 64 or more gives 0, by a negative
    amount is the runtime error `negative shift`, added to section 8's
    table. 6.9 now names `bit_xor` and `bit_shr` for its hash; 10.3 gains
    `@l0_bit_shl`, `@l0_bit_shr`, and `@l0_bit_count`, and says the logical
    three are LLVM's `and`, `or`, and `xor`. Left out, with the reasons in
    the changelog: a sign-copying shift, a bitwise not, rotation, and
    hexadecimal literals
  - 0031's rule checked: the names are new, and a program's own `def` of
    one still wins. Nothing in `compiler/` or `lib/` defined any of them
  - compiler: the checker's int groups and arities, and the emitter's
    instructions, runtime calls, and declarations; the compiler's source
    uses none of them, so one step, and the seed is refreshed
  - tests: `tests/io/bits` (every example in 6.10, the shift edges, and the
    CRC-32 check value 3421780262), `tests/io/bits_negative_shift`, five
    cases in `tests/compiler/check_errors`, and `tests/unit/sums_test.l0`.
    `bundle_prelude` and `emit_tail` blessed for the three new declarations
    in every module's header, and nothing else
  - **0055's sums rewritten** as `tests/unit/sums.l0`: 18 published vectors
    pass, the same sums on 100 MB in 2.33 s of user time against 9.90 s for
    the workaround (4.2 times), 268 lines against 400. `cksum` and `shasum`
    together take 0.35 s; the rest of the gap is reading a byte at a time
    and an eight-field state per round, which is 0060's business, not this
    item's
  - docs: `lib/examples.l0` gains a bits section (a set in an int, and
    CRC-32 without a table) with two tests; the shipped skill a paragraph
    on bits; `lib/AGENTS.md` and the repository's skill name them
  - both suites green (63, 121); fixpoint at 1,235,167 bytes, seed
    refreshed and reproduces itself; `tools/linux-test.sh arm64` green
    (63, 121); amd64 not run
  - next: 0061
