# 0039: The library declares Option and Result

Kind: tooling
Status: done, changelog "The library declares Option and Result, and no
language change for it"
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
- 2026-10-02: done. `(Option T)` and `(Result T E)` are in `lib/io.l0`,
  with `;;` docs, and `tests/io/libdoc/index.txt` re-pinned. The open
  questions, settled (reasons in the changelog):
  - Option and Result only; no pair, since every two-value type here has
    a name that says more than `Pair` would
  - `lib/io.l0`, keeping its name: a new file costs `tools/l0`,
    `tools/bundle.sh`, the install layout, and 16 `.extra` files for one
    `l0 doc` heading. Its header now says stage 0, not I/O, decides what
    goes in it
  - moved: `lib/examples.l0` (`Maybe` replaced by the library's `Option`,
    a new `parse_number` returning a `Result`, `Parsed`'s `Ok` renamed
    `Num`), `tests/unit/kvlog.l0` (`Loaded` and `Lookup` gone). Own `Ok`
    beside the library's: `tests/unit/shadow_test.l0`'s `test_own_ok`,
    and calc and 0028's json pass unchanged. 0028's json has one failing
    test, `test_golden_sample`, which opens `testdata` by a relative path
    and fails the same way without this change
  - the shipped `l0-code` skill says to use the library's types; the
    shipped skill and `lib/AGENTS.md` no longer say there is no clock
  - evidence for 0038, and against it: with `E` a parameter, no `Ok` or
    `Err` takes its type from its argument, so each is written with its
    type (6 in kvlog, 3 in the examples). Parametric functions would not
    lower that, since a helper making an `Err` has a `T` nothing
    determines. What they would add is helpers over `Option` and
    `Result`; neither moved program wanted one yet
