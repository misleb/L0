# 0042: `eq` compares two values of any type

Kind: language
Status: done, changelog "`eq` compares two values of any type"
Needs: 0041

## Why

A function with type parameters cannot compare its elements, so every
membership test, lookup, and equality over anything but `int` is written
once per type ([0041](0041-comparing-any-type.md) counts about 47 such
functions in maintained code):

```
(def (member T) ((x T) (xs (list T))) bool
  (if (is_empty xs)
      false
      (if (eq x (head xs)) true (member x (tail xs)))))

(def main () int
  (if (member "b" (split_spaces "a b c")) 0 1))
```

```
$ tools/l0check lib/io.l0 tmp/0041/member.l0
tmp/0041/member.l0:4:11: error: an argument of eq must be int, but this is T
```

## The change, as 0041 sketched it

- `eq` becomes `T, T -> bool`: true when the two values are the same
  value. int and bool compare as values. Lists and arrays are the same when
  they have the same length and pairwise the same elements. Data values
  are the same when they have the same constructor and pairwise the same
  fields. Bytes are the same when they hold the same bytes. Never by
  address, sharing, or how a value was built: `(eq "ab" (cons 97 "b"))` is
  true. No stack in proportion to size or depth, and no runtime error but
  `heap exhausted`.
- spec 4.1, 6 (the table, the paragraph at the end of 6 that says to write
  a function, and a new subsection), 6.6, 10.1 (data-block padding is 0; a
  bytes block has mask bit 1), and 10.3 (`@l0_equal`; `eq` is `icmp` for
  uncounted types and a runtime call for counted ones; `eq` reads its
  arguments without consuming them)
- the checker accepts `eq` on two arguments of one type; the emitter
  chooses `icmp` or `@l0_equal` by whether the type is counted, which in a
  generic copy is all it knows
- the runtime gains `@l0_equal`, an iterative walk with an explicit
  worklist that returns early when both sides are the same pointer, and
  bytes blocks gain mask bit 1
- `lt`, `le`, `gt`, and `ge` stay int-only

## Done when

- the l0-bootstrap checklist: spec, changelog, both suites green, fixpoint,
  seed refreshed, since programs need a seed that knows `@l0_equal`
- `tests/unit/eq_test.l0`: int, bool, strings built different ways, nested
  lists, data values with equal and different tags and nullary
  constructors, arrays of ints and of pointers, empty ones, bytes, and both
  copies of a generic function
- `tests/io`: a list of a million elements and a value nested 100,000 deep
  under a small `L0_STACK_MB`; `L0_RC_CHECK` showing `eq` neither consumes
  nor leaks; a parameter used only by `eq` stays read-only
- the two goldens pinning today's error re-blessed on purpose, and a new
  case for `eq` given two different types
- `tools/linux-test.sh`, since the runtime changes

## Log

- 2026-10-02: opened from 0041's finding.
- 2026-10-05: implemented, as sketched.
  - spec: 4.1, the table and end of 6, 6.6, new 6.8, 10.1 (padding is 0;
    bytes have mask 2), 10.2, 10.3 (`@l0_equal`, how `eq` is emitted, `eq`
    borrows and keeps a parameter read-only). Changelog "`eq` compares two
    values of any type"
  - checker: `check_eq`, whose error is "the second argument of eq must be
    X, but this is Y". Emitter: `eq` on a counted type calls `@l0_equal`,
    and `eq` is borrowing. Runtime: `@l0_equal`, a walk with a pair
    worklist of its own that queues words last first, and `memcmp` for int
    arrays and bytes; `bytes_mark` sets mask 2
  - the compiler's output gains only `declare i64 @l0_equal(i64, i64)`:
    stage 1 from the old seed is 32 bytes short of stage 2, exactly that
    line, and `emit_tail` and `bundle_prelude` differ by it alone
  - tests: `tests/unit/eq_test.l0` (9 tests across every kind, constructor
    widths, the same binding twice, both copies of a generic `member`);
    `tests/io/eq_deep` (a million-element list, 1,000 strings, 100,000-deep
    nesting, on a 1 MB stack under `L0_RC_CHECK`); `tests/io/eq_read_only`
    (an IR check that bytes parameters used only by `eq` are read-only and
    the loop counts nothing); `tests/check/types` gains the mismatch, with
    stage 0's verdict and the compiler's wording. Re-blessed on purpose:
    `check_errors` (its `eq` on bytes is now a type mismatch) and
    `check_fn_params` (generic `eq` is now ok, plus a mismatch and `lt` at
    T)
  - docs: both `l0-code` skills, README, `list_eq`'s doc, and
    `lib/examples.l0` gains `count_of`
  - both suites green (63, 110), fixpoint holds, seed refreshed, and the
    installed `tools/l0` rebuilt from the seed runs `eq` on lists
  - `tools/linux-test.sh` on linux/arm64 (Ubuntu clang 18.1.3): both
    suites green. amd64 not run
  - next, from 0041: a tooling item moving the library onto `eq` (generic
    `member` and `index_of`; `strs_eq` and `check_bool` in `lib/test.l0`
    can use it now that the seed knows it)
