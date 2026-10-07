# 0058: bitwise operations

Kind: language
Status: queued
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
