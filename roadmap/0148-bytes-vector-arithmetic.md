# 0148: dot products over bytes, and narrow floats read from them

Kind: language
Status: done, changelog "Dot products over bytes, and narrow floats read from them"
Needs: nothing

## Why

L0S's request, `probes/vector/REQUEST-vector-arithmetic.md` in L0S, for
its roadmap 0060, Whistle, a 16.9 MB speech model, run on a Pi 5 with no
host. Nearly all of a model's time is one loop: a row of int8 weights
times a vector of int8 activations, summed. In L0 that loop is a
`bytes_get`, a sign fix, a `mul`, an `add`, and a tail call per element,
with a bounds check in each `bytes_get`; L0S's probe, a 768 by 768 int8
matrix times a vector, measures it at 1930 ps per multiply-add on an
x86_64 host, against 274 ps for scalar C and 35 ps for C the compiler
vectorised. A 10 s clip is billions of multiply-adds: tens of seconds at
L0's rate, under a second at the vector unit's. Nothing in L0 reads a
float32 or float16 from bytes either, so weights stored as FP16 cannot be
read in place.

This is the first item taken for speed alone, against the README's line
that speed alone does not justify a change. It clears that line because
the program cannot exist without it, not because it would be nicer: a
55-fold gap is the difference between a model that answers and one that
does not, and no loop written in L0 can close it, since every element
costs a call and a check. 0107 took `bytes_slice` and `bytes_concat` on a
cost argument of the same kind.

`roadmap/0148/why.l0`, cut down from L0S's `dot.l0`:

```
(def row ((w bytes) (x bytes) (r int) (n int)) int
  (bytes_dot_i8 w (mul r n) x 0 n))

(def gain ((g bytes) (i int)) float
  (bytes_get_f16 g (mul i 2)))
```

```
roadmap/0148/why.l0:8:3: error: unknown function bytes_dot_i8
roadmap/0148/why.l0:12:3: error: unknown function bytes_get_f16
```

## The rule

Four builtins over ranges of `bytes`, each a pure function of its bytes as
`bytes_get` is, each checking its ranges once before anything, and each
the same on every target:

- `(bytes_dot_i8 a i b j n)`: the sum over k below n of the signed bytes
  `a[i+k]` times `b[j+k]`, exact, as an `int`
- `(bytes_dot_f32 a i b j n)`: the n binary32s at `a` from byte `i` times
  the n at `b` from byte `j`, each product and sum in binary32, in an
  order the spec fixes: four partial sums, element k in sum k mod 4, the
  sums then added as (0 + 1) + (2 + 3). So the result is the same on a
  vector unit of four lanes, in scalar code, and on every compiler, and
  the runtime may use the vector unit for it
- `(bytes_get_f32 b i)` and `(bytes_get_f16 b i)`: the binary32 or
  binary16 at bytes `i` on, little-endian, as a `float`, exactly; a NaN
  is the one NaN of 6.17

Left to 0149: `bytes_axpy_f32` and `bytes_set_f32`, which L0S also asked
for. They change a byte, which spec 6.6 says no builtin does, so they are
the first users of bytes updated in place, an item of their own.

The runtime writes each in LLVM IR with vector types, which LLVM lowers
to NEON on aarch64, SSE on x86_64, and scalar code on riscv64, whose
targets have no vector extension; the IR carries no fast-math flags, so
nothing is fused or reordered, and the order above is what runs. The
binary16 is widened by integer arithmetic, not `fpext half`, which on x86
and every freestanding target would call a compiler-rt routine no L0
program links.

## Done when

- the checklist in the l0-bootstrap skill, and the places "Adding a
  builtin" lists
- spec 6's table and 6.6 give the four, with the float order and the
  range rule; 8's table has their range error; 10.3 declares them and
  lists them as reading without consuming and as keeping a parameter
  read-only; the changelog says why, with the measurement
- `tests/unit/bytes_test.l0` checks each: the int8 dot with negative
  bytes and an unaligned offset, the float32 dot where its order shows
  (lanes that cancel where a left-to-right sum would not), a tail that is
  not a multiple of four, and the narrow reads with a subnormal, an
  infinity, a NaN, and a negative zero; `tests/io` has the range error;
  `check_errors` the arity and type errors
- L0S's probe, `dot.l0` with its loop as a `bytes_dot_i8` a row, measured
  against the numbers above, in the Log
- `tools/test.sh`, `--compiled`, and `--virt` green on both boards; the
  fixpoint holds; the seed refreshed
- `roadmap/l0s-adoption.md` says what L0S gains, with the snippet and a
  grep for a `bytes_get` loop that sums products
- L0S told, by the Status line of its request

## Log

- 2026-10-31: opened from L0S's request, at the user's request, as the
  pure four of the six it asked for; the in-place two are 0149. Started.
- 2026-10-31: spec, changelog, checker, emitter, runtime, and tests
  written; `why.l0` checks and runs. L0S's probe, its `row_dot` as one
  `bytes_dot_i8` a row (`tmp/0148/dot_bulk.l0`), on this x86_64 host:
  1898 ps per multiply-add as it is, 140 with the builtin, the same
  checksum 32286750; 13.5 times faster, against scalar C's 274 and
  vectorised C's 35. The host loop is SSE2 baseline, 24 instructions per
  16 bytes; a first version that reduced every block measured the same,
  so the chunked vector accumulator stayed for aarch64's sake, where the
  loop is two loads, `smull`/`smull2`, and four `saddw` per 16 bytes, and
  the float loop unfused `fmul`/`fadd` on four lanes, read from `clang
  --target=aarch64-none-elf -S`. Neither `-mcpu=cortex-a76` nor the base
  target reaches `sdot`; that needs LLVM's partial-reduction intrinsic or
  the per-block reduce with the CPU named, and waits for a number from a
  board. Not run on a Pi 5.
- 2026-10-31: done. `tools/test.sh` 74, `--compiled` 178, the fixpoint
  holds, `--virt` 427 passed on both boards; the seed refreshed. The
  `l0-code` skill, `lib/examples.l0`, and `roadmap/l0s-adoption.md` §14
  say what is new. Not run on macOS or a Pi 5. Not committed; L0S not yet
  told. 0149 started on it at once.
