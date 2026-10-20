# 0096: float_sqrt

Kind: language
Status: done
Needs: 0094

## Why

0094 left square root out "until a program needs it" (changelog "Floating
point"). L0S's `tools/mkfont`, for its 4K face, does:

- curve flattening: a Bézier curve is cut into n >= sqrt(bend / (8 tol))
  lines, today `rast_quad_steps` and `rast_cubic_steps` in `raster.l0`, over
  an integer `isqrt`
- stroke outlines: the unit normal of each line is its direction divided by
  sqrt(dx^2 + dy^2), today `isqrt` at `shape.l0:224`, which truncates
- arcs: the step that keeps a chord within tol of a circle of radius r is
  about sqrt(8 tol / r)

What cannot be written is `(float_sqrt x)`:

```
(def length ((dx float) (dy float)) float
  (float_sqrt (float_add (float_mul dx dx) (float_mul dy dy))))
```

A library version in L0 (Newton's method) is not correctly rounded without a
correction step, and a hardware square root is one instruction and exactly
rounded by IEEE 754 on both boards (`fsqrt` on aarch64, `fsqrt.d` on
riscv64) and amd64 (`sqrtsd`), so a builtin keeps 6.17's promise that every
host gives the same bits. The other way round, `isqrt` on a scaled
`float_to_int`, loses the precision floats were added for.

## Done when

- the `l0-bootstrap` checklist: spec (6 table, 6.17), changelog, both suites,
  the fixpoint
- `(float_sqrt x)` is IEEE squareRoot to nearest: -0.0 gives -0.0, +inf
  gives +inf, and a negative number, -inf, or NaN gives the one NaN
- tested on the host, both virt boards, and Linux arm64
- the `l0-code` skill and `lib/examples.l0` list it

## Log

- 2026-10-19: opened at the user's request, for L0S's 4K face. Absolute
  value is not wanted: one comparison writes it.
- 2026-10-19: done. `float_sqrt` lowers to `llvm.sqrt.f64`, then the NaN
  select, so a negative argument gives the one NaN. Tested on the host and
  both boards (`tests/unit/float_test.l0`, bits from Python's `math.sqrt`),
  `--virt`, and Linux arm64; amd64 skipped at the user's word. Seed
  refreshed. L0S can use it after it updates its toolchain.
