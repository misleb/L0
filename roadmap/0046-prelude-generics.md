# 0046: the prelude takes back the generic definitions

Kind: language
Status: done, changelog "The prelude takes back the generic definitions,
and no language change for it"
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
- 2026-10-05: done.
  - `lib/prelude.l0` gained the lists-and-arrays and Option-and-Result
    sections, word for word, and its header and `;;;` say it is the part of
    the library that does no I/O and checks on its own (`tools/l0check
    lib/prelude.l0` passes alone). `lib/io.l0` lost them and says it is I/O
  - `compiler/lex.l0` lost its list-helper section; the compiler calls the
    prelude's generic `rev`, `append`, `length`, `any_eq`, and `index_of`.
    Also gone: the prelude's internal `rev_strs_onto`, whose callers
    (`split_spaces`, two in `compiler/parse.l0`, `tests/compiler/fmt.l0`)
    call `rev`
  - no name collides: nothing compiled in one group with the prelude (the
    compiler, its stage tests) declares any of the moved names
  - `tests/io/libdoc/index.txt` re-pinned; the diff is the nine entries
    moving from `io` to `prelude` and the two file summaries. Comments in
    `tests/unit/lists_test`, `shadow_test`, and `kvlog` name the prelude;
    README "The standard library" and the `l0-code` skill say where the
    definitions are
  - both suites green (63, 110); fixpoint at 1,167,452 bytes (from
    1,162,096); the compiler compiles itself in 0.16 s, as before; seed
    refreshed and reproduces itself; `tools/l0` rebuilt from it runs a
    generic program. No Linux run: the runtime and emitter are unchanged,
    and Docker is still down, so 0045's runs remain owed
  - `roadmap/0044/` deleted
  - next: 0047
