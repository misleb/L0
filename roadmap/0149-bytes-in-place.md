# 0149: bytes updated in place: a float32 written, and y made y + a·x

Kind: language
Status: done, changelog "Bytes are updated in place: a binary32 stored, and y made y + a·x"
Needs: 0148

## Why

L0S's request, `probes/vector/REQUEST-vector-arithmetic.md` in L0S, asks
for six builtins over bytes; 0148 takes the four that only read. The
other two write: `(bytes_set_f32 b i x)` stores one binary32, and
`(bytes_axpy_f32 y i a x j n)` makes the n binary32s of `y` from byte `i`
`y + a·x`, with `x`'s from byte `j`. Whistle's attention and norms keep
their activations as float32 in bytes and update them row by row, and a
copy of the whole vector per update would cost what the vector unit
saves.

Spec 6.6 says no builtin changes a byte, so bytes are never updated, in
place or otherwise. The roadmap has listed bytes that update in place as
open and waiting for code since the index's goals table was written; this
is that code. These two follow `array_set` (6.5): in place when nothing
else holds the value, else after copying it whole, with the same result
either way, and the hidden-copy warning of 0139 applying to them.

`roadmap/0149/why.l0`:

```
(def axpy ((y bytes) (a float) (x bytes) (n int)) bytes
  (bytes_axpy_f32 y 0 a x 0 n))

(def put ((b bytes) (i int) (v float)) bytes
  (bytes_set_f32 b (mul i 4) v))
```

```
roadmap/0149/why.l0:7:3: error: unknown function bytes_axpy_f32
roadmap/0149/why.l0:11:3: error: unknown function bytes_set_f32
```

## The rule

- `(bytes_set_f32 b i x)` is `b` with bytes `i` to `i+3` holding `x`
  rounded to binary32, to nearest, ties to even, little-endian; an `x`
  past binary32's range gives its infinity, and a NaN the binary32 NaN
  0x7FC00000. Unless 0 ≤ `i` and `i + 4` ≤ `(bytes_len b)`, a runtime
  error.
- `(bytes_axpy_f32 y i a x j n)` is `y` with each of its n binary32s
  from byte `i` made `y_k + a·x_k`, `a` rounded to binary32 first, the
  product and the sum each in binary32, `x_k` the binary32s of `x` from
  byte `j`; the same range rule as `bytes_dot_f32`, and if `x` and `y`
  are the same value its ranges may not overlap unless they coincide.
- Both consume their bytes as `array_set` consumes its array: in place
  when nothing else holds it, otherwise a copy, and 6.6's "bytes are
  never updated" becomes the rule 6.5 states for arrays.
- `bytes_axpy_f32` consumes `x` too, since a builtin borrows all of its
  pointer arguments or none. That is also what makes overlapping ranges
  of one value safe for free: when `x` and `y` are one block it is held
  twice, so `y` is copied before any write and `x` is read from the
  original. A NaN stored is 0x7FC00000, not the CPU's, whose sign differs
  between x86-64 and aarch64 and would show through `bytes_get`.

## Done when

- the checklist in the l0-bootstrap skill, and the places "Adding a
  builtin" lists
- spec 6's table and 6.6 give both and say when bytes change; 8's table
  has the range error; 10.3 says they consume their bytes and return it
  or a copy as `@l0_array_set` does; the changelog says why, and that
  6.6's restriction is given up
- the checker's hidden-copy warning covers both; `tests/compiler/
  warn_copy` has a case
- `tests/unit/bytes_test.l0` checks the write, the rounding to binary32,
  axpy in place and after a copy (`L0_ARRAY_STATS` in a `tests/io`
  test, as `fields_in_place` measures), and the range errors
- `tools/test.sh`, `--compiled`, and `--virt` green on both boards; the
  fixpoint holds; the seed refreshed
- `roadmap/l0s-adoption.md` and the `l0-code` skill's "nothing changes a
  bytes value" say what is now true
- L0S told, by the Status line of its request

## Log

- 2026-10-31: opened from L0S's request, at the user's request, as the
  two of its six that write; queued behind 0148.
- 2026-10-31: started as 0148 landed. Spec, changelog, checker, emitter
  (the copy warning names both), runtime (`bytes_own`, after `arr_own`),
  and tests written; `why.l0` checks and runs. `tests/io/bytes_in_place`:
  100,000 axpy steps over a threaded vector copy nothing, with a binding
  holding it copy once a step, 100,000 stores threaded copy nothing. The
  unit tests cover the rounding, the NaN, both infinities, overlap of a
  value with itself, and the copy a later use makes. Suites running.
- 2026-10-31: done. `tools/test.sh` 74, `--compiled` 179, the fixpoint
  holds, `--virt` 427 passed on both boards; the seed refreshed, once
  after 0148 and again here, so one seed carries both. The `l0-code`
  skill, `lib/examples.l0`, and `roadmap/l0s-adoption.md` §15 say what is
  new. Not run on macOS or a Pi 5. Not committed; L0S not yet told.
