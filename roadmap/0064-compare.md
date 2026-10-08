# 0064: `compare` orders two values of any type

Kind: language
Status: done, changelog "`compare` orders two values of any type"; passed
on Linux arm64
Needs: 0059

## Why

[0055](0055-programs-round-three.md)'s structures worker could not write a
heap or a balanced tree once for every element type:

```
(def (smaller T) ((a T) (b T)) T
  (if (lt a b) a b))
```

```
$ tools/l0check roadmap/0055/structures/limits/01-order-type-param.l0
roadmap/0055/structures/limits/01-order-type-param.l0:9:7: error: an argument of lt must be int, but this is T
```

The named workaround orders a closed sum, `Key = KInt int | KStr bytes`,
5.2 times slower on the heap and closed to records.
[0059](0059-compare-or-function-values.md) found 11 of the 21 orderings here
structural and 8 more structural once a key value is built; `key_cmp` in
`roadmap/0055/structures/kmerge/key.l0` is exactly the structural order on
`Key`.

## Done when

- the spec has `(compare a b)`: -1, 0, or 1, `b` of `a`'s type, 0 exactly
  when `eq` is true, the order fixed per kind as 0059's finding gives it
  (ints signed, false before true, lists, bytes, and arrays
  lexicographically with a proper prefix first, data values by constructor
  position and then fields); 10.3 has `@l0_compare`, and says `compare` on
  `int` and `bool` is instructions; the changelog says why, and why not
  function values yet
- the runtime's walk visits in order with a worklist, needing no stack, and
  allocates nothing a program can see
- tests: every kind and its edges, constructors of different widths, both
  copies of a generic function, a deep and a long value under a small
  stack, and the checker's mismatch; stage 0 is not extended
- 0055's `limits/01` checks with `compare` in place of `lt`
- the compiler and the prelude use none of it; the l0-bootstrap checklist,
  with the seed refreshed, and a Linux run

## Log

- 2026-10-07: proposed by 0059.
- 2026-10-08: done.
  - spec: new 6.11, the table and end of 6, 4.1, 6.6 (bytes are ordered),
    6.8's end, 10.2 (a copy decides `compare` as it does `eq`), 10.3
    (`@l0_compare`, how `compare` is emitted, that it borrows, and that a
    parameter used only by it is read-only)
  - runtime: `@l0_compare`, a walk of both values together in order with a
    worklist of three-word entries, a block's words queued last first so
    word 0 is taken next; arrays of counted values queue their lengths
    beneath their elements; `memcmp` for bytes, a signed loop for int arrays
  - compiler: `check_compare`, with "the second argument of compare must be
    X, but this is Y"; `compare` borrows; on a counted type a call of
    `@l0_compare`, on `int` or `bool` `icmp sgt`, `icmp slt`, and a `sub`.
    The compiler and the prelude use none of it
  - tests: `tests/unit/compare_test.l0` (10 tests: every kind and its
    edges, constructors of different widths, a key, agreement with `eq`,
    both copies of a generic `smaller`); `tests/io/compare_deep` (a
    million-element list and 100,000-deep nesting on a 1 MB stack under
    `L0_RC_CHECK`); `tests/io/compare_read_only` (an IR check: no counting,
    one runtime call for the lists, instructions for the ints); four cases
    in `check_errors`. `bundle_prelude` and `emit_tail` blessed for the one
    new declaration
  - 0055's `limits/01-order-type-param.l0` with `compare` in place of `lt`
    checks and runs through the refreshed seed
  - docs: the shipped skill's type-parameter and ordering paragraphs, with
    ordering by a key and the bignum caution; the repository's skill
  - both suites green (65, 128); fixpoint at 1,259,809 bytes, seed
    refreshed and reproduces itself; `tools/linux-test.sh arm64` green
    (65, 128)
  - next: 0065, the prelude's sort, min, and max over `compare`, now that
    the seed knows it
