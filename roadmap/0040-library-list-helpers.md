# 0040: The library's list helpers work at every element type

Kind: language
Status: done, changelog "The library's list helpers take every element
type, and no language change for it"
Needs: 0038

## Why

[0038](0038-parametric-functions.md) lets a function be written once for
every element type, and the library is where most of the duplicated helpers
belong: the prelude's `rev`, `rev_onto`, `length`, and `append` are
`(list int)` only, with `rev_strs_onto` beside them and `strs_eq` in
`lib/test.l0`, and programs write their own per type, such as kvlog's
`rev_entries` and the compiler's `rev_*_onto` family.

## Open questions

All settled; the changelog entry has the reasoning.

- names: the same names. The four left `lib/prelude.l0` for generic
  versions in `lib/io.l0`, and the compiler keeps `(list int)` copies at the
  top of `compiler/lex.l0`. This touches the prelude and the compiler, so
  the item became a language item
- which helpers: `rev`, `rev_onto`, `append`, `length`, and `array_resize`.
  No `nth`, since no program here indexes a list
- `l0 doc`: it did not read a `(def (name T)` head, and is fixed
- programs: kvlog, array_paths, and its graph.l0

## Done when

- the helpers are in the library with `;;` docs that `l0 doc` shows
- at least two programs here use them in place of their own

## Log

- 2026-10-02: proposed from 0038.
- 2026-10-02: done. The user chose the same names over new ones in
  `lib/io.l0`.
  - `lib/io.l0` has generic `rev_onto`, `rev`, `append`, `length`, and new
    `array_resize`. `lib/prelude.l0` lost the `(list int)` four, and
    `rev_strs_onto` is internal. `compiler/lex.l0` has the compiler's copies
  - `tools/l0` doc takes a declaration's name from inside a parenthesized
    head; `tests/io/libdoc/index.txt` re-pinned
  - kvlog drops `rev_entries`, array_paths drops `count_fields`, and graph
    drops `copy_into` and its `rev_strs_onto` call
  - `tests/unit/lists_test.l0`: ten tests at `int`, string, data, `bool`,
    and `Option` elements, and array growth and shrinking with counted
    elements, under `L0_RC_CHECK`. `tests/io/parametric_data.extra` now
    lists `lib/io.l0`
  - both suites green (63, 107), fixpoint holds, seed refreshed. No Linux
    run: the runtime and the emitter are unchanged
