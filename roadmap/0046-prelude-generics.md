# 0046: the prelude takes back the generic definitions

Kind: language
Status: queued
Needs: 0045

## Why

[0044](0044-compiler-free-of-stage0.md): the generic list and array helpers
and `Option` and `Result` live in `lib/io.l0` only because stage 0 ran the
prelude, and `compiler/lex.l0` keeps `(list int)` copies of `rev_onto`,
`rev`, `append`, `length`, `length_onto`, `any_eq`, `index_of_from`, and
`index_of` for the same reason. `roadmap/0044/proto.diff` makes those
copies generic in the concatenated compiler source, and the seed
bootstraps the result to a fixpoint.

## Done when

- `rev_onto` to `index_of_from`, `array_resize`, `array_copy_onto`,
  `Option`, and `Result` are in `lib/prelude.l0`, and `lib/io.l0` holds I/O
  only, with each file's `;;;` description saying so
- `compiler/lex.l0` has no copies of them, and the compiler calls the
  prelude's
- `tests/io/libdoc/index.txt` re-pinned, and the `l0-code` skills say where
  the definitions live
- both suites green, the fixpoint holds, the seed refreshed, and the
  changelog says why, superseding "Why lib/io.l0, though they are not I/O"
- `roadmap/0044/` deleted, since this item is the real thing it prototyped

## Log

- 2026-10-05: queued by 0044.
