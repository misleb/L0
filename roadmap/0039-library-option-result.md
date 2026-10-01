# 0039: The library declares Option and Result

Kind: tooling
Status: proposed
Needs: 0037

## Why

[0035](0035-type-parameters.md) found programs declaring the same result,
option, and pair types once per element type, and the compiler has ten
`Result`-shaped types. [0036](0036-parametric-data.md) made one declaration
serve every element type, and [0037](0037-library-type-names.md) made it
safe for the library to declare one: a program's own `Ok` now shadows the
library's instead of colliding with it.

## Open questions

- which types earn a place: `Option` and `Result` are the evident ones; a
  pair is less clear, since a named type usually reads better
- they go in `lib/io.l0`, not `lib/prelude.l0`, since stage 0 runs the
  prelude and cannot parse a type parameter; whether that file's name
  still fits
- which programs move onto them as evidence, such as 0014's json with its
  `PJ` and `PS`, and kvstore's five result types. Functions are still
  monomorphic, so helpers over `Option` are per element type until
  [0038](0038-parametric-functions.md)

## Done when

- the types are in the library with `;;` docs that `l0 doc` shows
- at least two programs here use them in place of their own, and a
  program that declares its own `Ok` still builds beside them

## Log

- 2026-09-30: proposed from 0037.
