# 0094: floating point

Kind: language
Status: done
Needs: nothing

## Why

L0 has only 64-bit integers, so any program that measures, scales, or turns
works in fixed point it builds itself. L0S, the kernel's own project, draws
its font's circles from a table of sines in 1/65536, `shape_sines` in
`tools/mkfont/shape.l0:144` there, holding sin of 5k degrees for k from 0
to 18, so a shape can turn only by a multiple of 5 degrees. 0028's json
(`roadmap/0028/text/limits/03-no-floats.l0`) earned floating point before,
for printing numbers as Python does, and 0055 named it as not yet earned;
that half, the text conversions, is not this item.

What L0S would write, `roadmap/0094/why.l0`:

```
(def radians ((deg int)) float
  (float_div (float_mul (float_from_int deg) 3.141592653589793) 180.0))

(def on_circle_x ((cx int) (r int) (deg int)) int
  (add cx (float_to_int (float_mul (float_from_int r) (float_cos (radians deg))))))
```

```
$ tools/l0check roadmap/0094/why.l0
roadmap/0094/why.l0:5:26: error: unknown type float: a type is int, bool, bytes, (list T), (array T), or a data type, whose name starts uppercase
roadmap/0094/why.l0:9:36: error: unknown function float_from_int
roadmap/0094/why.l0:12:36: error: unknown function float_from_int
```

`float_sin` and `float_cos` are 0095's, in the library; this item gives the
type, its literals, and the builtins they are written with.

## What already holds

- **A float fits the value representation.** Every value is one `i64`
  (spec 10.1), so a binary64 is one word that is not a pointer: no change to
  calling conventions, headers, masks, or the allocator. An operation is
  `bitcast i64 to double`, the instruction, and back.
- **Both CPUs keep a float's registers across a trap.** Both boot files
  enable the FPU, and the trap frames save q0 to q31 with fpcr and fpsr
  (`runtime/arch/aarch64/boot.ll:113`) and f0 to f31 with fcsr
  (`runtime/arch/riscv64/boot.ll:111`), so a process under any kernel here
  or L0S keeps its floats with no kernel change.
- **What Tier 1 needs lowers to instructions on both boards.** Checked with
  LLVM 23 at `-O0` for `aarch64-none-elf` and for `riscv64-unknown-elf`
  with the virt manifest's flags (2026-10-19): `sitofp`, `fdiv`,
  `llvm.sqrt` (`fsqrt`), and `llvm.fptosi.sat.i64.f64` (`fcvtzs`;
  `fcvt.l.d` with a NaN check) call nothing. `llvm.floor` is `frintm` on
  aarch64 and an `fcvt` pair on riscv64, but `callq floor@PLT` on amd64
  Linux, a host the suite runs on, so `floor` is left out (below). A
  division of two exact constants was folded at `-O0` on both.

## Decisions, with the lean for each

1. **Names.** L0 has no overloading, and `add` stays `int`'s. The builtins
   are `float_add float_sub float_mul float_div float_neg`, `float_lt
   float_le float_gt float_ge`, `float_from_int float_to_int`, and
   `float_bits float_from_bits`, prefixed as `bit_` and `array_` are.
   `float` is a type only where a type is expected and is not reserved, as
   `bytes` is (spec 2.3), so no program loses a name.
2. **The word holds the float's total-order key, not its bits.** For bits
   `b`, the word is `b xor ((b ashr 63) lshr 1)`: a positive float is its
   bits, and a negative one has bits 0 to 62 flipped. As signed integers,
   keys are in IEEE 754 totalOrder (-NaN, -inf, ..., -0, +0, ..., +inf,
   +NaN), and the map is its own inverse. So `eq`, `hash`, and `compare`
   need no change in the compiler or the runtime, on a float or on any
   structure holding one, and a float can key a `(Map K V)`: the runtime
   compares a structure's non-pointer words as signed integers, which on
   raw bits would put -2.0 above -1.0. The spec must then say that `eq` is
   identity of keys, so `(eq 0.0 -0.0)` is false and a NaN is `eq` to
   itself, while `float_lt` and its siblings are IEEE's, false whenever an
   argument is NaN. `float_bits` gives IEEE bits, decoded. The rejected
   alternative is the checker refusing `compare` on any type that mentions
   `float`, which would keep floats out of sorted lists and map keys for
   nothing.
3. **NaN is one value.** CPUs disagree on the NaN an operation produces:
   riscv64 always gives 0x7FF8000000000000, aarch64 passes an operand's
   payload on unless FPCR.DN is set, and amd64's default is
   0xFFF8000000000000. Under decision 2 that difference is visible to `eq`,
   `hash`, and `compare`, so the same program would differ by CPU. Lean:
   every operation that can produce a NaN selects 0x7FF8000000000000 when
   its result is unordered (`fcmp uno` and `select`), and `float_from_bits`
   does the same, so a NaN in L0 is always that one. Measure the cost in
   step 5; if it is large, setting FPCR.DN at start on aarch64 covers the
   boards, but not amd64.
4. **Literals are the ones a single IEEE division gets exactly right.** LLVM
   IR accepts a decimal `double` constant only if it is exact, so `0.1` must
   go out as bits, and the compiler cannot use floats to compute them.
   Clinger's fast path avoids that: a literal is `-`? digits `.` digits;
   with the point removed and trailing zeros dropped, its digits as an
   integer m must be at most 2^53 and the digits after the point, k, at
   most 22. Then m and 10^k are both exact binary64s, whose bits the
   compiler computes with integers, and `fdiv double M, P` is the correctly
   rounded value by IEEE 754 itself, whether LLVM folds it or the CPU runs
   it. A `-` is `float_neg` after, so `-0.0` is negative zero. Any other
   literal is a compile error naming the limit; `float_from_bits` writes
   every other value. `3.141592653589793` fits (m is 3141592653589793,
   below 2^53); `0.1000000000000000055` does not. No exponent syntax, until
   a program needs it.
5. **`float_to_int` truncates toward zero and saturates**
   (`llvm.fptosi.sat`): NaN gives 0, and a value past the range gives
   -2^63 or 2^63 - 1, never poison, as `add` never traps. `float_from_int`
   rounds to nearest, ties to even. `float_div` by zero gives an infinity
   or NaN, unlike `div` (spec 6.1); no float operation is an error of
   section 8.
6. **Rounding is to nearest, ties to even, always.** Nothing in L0 changes
   the mode, and the trap frames keep it.
7. **Left out until a program needs them:** `float_sqrt`, `float_abs`,
   `float_floor` (amd64 calls libm for it, so it would need a runtime
   function in IR), exponent literals, and printing and parsing text
   (0028's json; Ryu and a correctly rounded parser, a later item).

## Order of work

Spec first, as the `l0-bootstrap` skill orders it. The compiler and the
prelude use none of it, so this is one bootstrapped step; the library's
`float_sin` and `float_cos` are 0095, after the seed is refreshed.

1. **Spec and changelog.** 2.4 float literals, 3 the type, 6 a section
   for the builtins (with eq, hash, and compare on floats in 6.8, 6.9, and
   6.11), 10.1 the word as the key, and how each is emitted. Changelog:
   why now (L0S), why keys (decision 2), why one NaN, why fast-path
   literals, and what was left out.
2. **Compiler.** `lex.l0`: a float token holding m, k, and the sign;
   `parse.l0`: `TyFloat`, `EFloat`, `ty_str`; `check.l0`: the builtin
   groups, arities, and types, `float` as a type name like `bytes`, and
   the literal limit's error; `emit.l0`: the builtins inline (encode,
   instruction, NaN select, decode), `builtin_type`, `ty_is_ptr` false,
   and literals as `fdiv` of two hex constants.
3. **Tests.** Stage 0 is frozen and knows no floats, so nothing goes in
   `tests/lang` or `tests/check`. `tests/unit/float_test.l0`: each
   builtin, against bits computed outside L0 (Python's `struct`); keys in
   totalOrder; `eq`, `hash`, and `compare` on floats and on a data value
   holding one, and a float-keyed `Map`; -0.0, both infinities, NaN from
   each operation giving the one NaN; `float_to_int` at NaN and past
   both ends; literals at the fast path's edges (m = 2^53, k = 22).
   `tests/compiler/check_errors`: a literal past the limit, `float` where
   `int` is wanted, and each builtin's arity. `bundle_prelude` and
   `emit_tail` re-blessed if a `declare` is added.
4. **Both suites and the fixpoint**, then `tools/test.sh --virt` on both
   CPUs, so the same bits come out on aarch64 and riscv64, and
   `tools/linux-test.sh` on arm64 and amd64.
5. **Measure the key and the NaN select.** A loop of float arithmetic
   against the same with raw bits and no select, at `-O2`, written down
   here. If either costs much, say so in the changelog and decide there.
6. **Refresh the seed**, which 0095 needs. Committing is the user's call.

## Done when

- the `l0-bootstrap` checklist: spec, changelog, both suites, the fixpoint,
  and the seed refreshed
- `roadmap/0094/why.l0` without its `float_cos` and `float_sin` passes
  `tools/l0check`
- `tests/unit/float_test.l0` passes on the host, on both virt boards, and
  on Linux arm64 and amd64, with the same bits everywhere
- step 5's measurement is in the Log

## Log

- 2026-10-19: opened at the user's request, after an estimate of what
  floating point costs: the type and builtins here, sin and cos for L0S in
  0095, and text conversion later. Checked that both trap frames already
  keep the FPU's registers and which operations lower to instructions on
  both boards and amd64. Queued; next is step 1.
- 2026-10-19: started. Step 1 done: spec 2.1 (float literals), 2.3, 3, 6
  table, 6.8, 6.9, 6.11, 6.17 (new), 10.1, and the changelog entry
  "Floating point". The spec says `float_neg` of the NaN is the one other
  NaN, 0xFFF8..., a refinement of decision 3. Next is step 2, the
  compiler: lex.l0, parse.l0, check.l0, emit.l0.
- 2026-10-19: steps 2 to 6 done. A float literal is a token (the IEEE bits
  of m and of 10^k, computed in the lexer with integers) and an `EFloat`
  expression, emitted as `fdiv double` of two hex constants, so the
  checker has no literal limit to check: the lexer reports it. Passed:
  `tools/test.sh`, `--compiled`, the bootstrap fixpoint, `--virt` on both
  CPUs, `tests/unit/float_test.l0` on the host and both boards, and Linux
  arm64. Linux amd64 was skipped at the user's word (too slow). Step 5: a
  dependent chain of one `float_mul` and one `float_add` per iteration ran
  at 9.8 ns, against 1.3 ns for an int `mul` and `add` chain, -O2, 300M
  iterations, on the host. Most of that is the key's decode and encode and
  the NaN select, since each operation does both; not measured against raw
  bits, so the split is not known. Fine for L0S's circles; revisit if a
  program's hot loop is float arithmetic. Seed refreshed. 0095 is next.
