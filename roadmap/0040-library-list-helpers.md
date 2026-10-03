# 0040: The library's list helpers work at every element type

Kind: tooling
Status: proposed
Needs: 0038

## Why

[0038](0038-parametric-functions.md) lets a function be written once for
every element type, and the library is where most of the duplicated helpers
belong: the prelude's `rev`, `rev_onto`, `length`, and `append` are
`(list int)` only, with `rev_strs_onto` beside them and `strs_eq` in
`lib/test.l0`, and programs write their own per type, such as kvlog's
`rev_entries` and the compiler's `rev_*_onto` family.

## Open questions

- names: the prelude's `rev` and `length` already take the obvious names,
  and a generic `rev` cannot sit beside them in one group. The prelude
  cannot hold a generic one while stage 0 runs it, and the compiler calls
  the prelude's. Whether `lib/io.l0` gets new names, or the prelude's
  `(list int)` functions move out of the prelude, which the compiler would
  then have to define for itself
- which helpers: `rev`, `rev_onto`, `length`, `append`, `nth`, and array
  growth are the ones 0035 counted; anything that compares elements cannot
  be generic, since `eq` takes only `int`
- whether `l0 doc`, which reads `(def name` lines, shows a `(def (name T)`
  header correctly
- which programs move onto them as evidence

## Done when

- the helpers are in the library with `;;` docs that `l0 doc` shows
- at least two programs here use them in place of their own

## Log

- 2026-10-02: proposed from 0038.
