# 0030: Read-only parameters

Kind: language
Status: done, changelog "Read-only parameters"; Linux not yet run
Needs: 0029

## Why

From [0028](0028-programs-with-arrays.md), `0028/grids/limits/02-read-only-helper-refcounts.l0`:
calling a function that only reads an array still costs an increment in the
caller and a release in the callee, and the release is a runtime call that
may free, so nothing can pair them away. 50 million lookups through a helper
taking three arrays take 0.27 s; taking the ints instead 0.09 s; inline 0.07
s. Writing sudoku's candidate check inline instead of as a helper took the
99-puzzle run from 0.29 s to 0.16 s. So the cost pushes agents toward
inlining by hand, the opposite of readable code.

No syntax is needed: a parameter the callee never consumes (it only reads it
with `head`, `tail`, `is_empty`, `array_get`, `array_len`, `match`, or passes
it on to another borrowed position) could be passed without a reference.
Section 10.3 fixes when references are taken, so it would have to say so.

## Done when

The l0-bootstrap checklist, plus the limit program and sudoku re-measured,
and the compiler on itself measured, since it is the largest program there
is.

## Log

- 2026-09-28: opened from 0028, by the user's choice.
- 2026-09-29: renamed from "borrow a parameter the function only reads", so
  nobody reads Rust's borrowing into it. Done. A whole-program fixpoint over
  the flags, a match on a read-only parameter binding its read-only fields
  without references, and the pad table made a hash-keyed tree. Measured:
  the helper 0.26 s to 0.10 s, sudoku 0.29 s to 0.15 s with identical
  output and no copies, the compiler unchanged at 106 ms. Two mutations
  checked: without tail-call demotion the bootstrap fails at once (LLVM
  rejects a release after a musttail call); with a match counted as a read
  whatever its fields, `tests/io/array_state` fails with 400,000 copies,
  which is the flaw the first version had. `tests/lang/read_only` covers the
  shapes. Both suites green on macOS; Docker was down, so the Linux runs
  are owed. Next is 0025.
