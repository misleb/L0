# 0043: The library and the suite's programs use eq

Kind: language
Status: done, changelog "The library compares with eq, and no language
change for it"
Needs: 0042

## Why

[0042](0042-eq-any-type.md) made `eq` compare two values of any type, and
the seed knows it, but the library still compares by hand:

- `any_eq` and `index_of`, the prelude's membership and position tests,
  take only a string in a list of strings. A program testing an int or a
  data value for membership writes its own, as `tests/unit/eq_test.l0`'s
  `member` and 0028's maze_test `member` do
- `lib/test.l0`'s `check_strs` compares through `strs_eq`, a copy of
  `list_eq` one level up, and `check_bool` writes `(if got want (not
  want))` for want of `eq` on bools
- the suite's programs call `list_eq` eleven times: kvlog, graph.l0,
  write_failure, array_myers, and csvcol_test

## Done when

- `any_eq` and `index_of` take a value and a list of any type, under the
  same names, in `lib/io.l0`; the compiler keeps its string copies, as 0040
  did for `rev`
- `lib/test.l0` uses `eq`, and `strs_eq` is gone
- the programs above use `eq` in place of `list_eq`, and `eq_test`'s
  `member` is `any_eq`
- both suites green, the fixpoint holds, the seed refreshed, and the
  changelog says why

## Log

- 2026-10-05: opened from 0041's recommendation and 0042's last Log line.
- 2026-10-05: done.
  - `lib/io.l0` has generic `any_eq`, `index_of`, and an internal
    `index_of_from`; `lib/prelude.l0` lost its string versions, and
    `compiler/lex.l0` keeps them for the compiler's 57 calls
  - `lib/test.l0`: `check_bool`, `check_str`, `check_strs`, and
    `check_file` use `eq`; `strs_eq` is gone
  - the eleven `list_eq` calls in kvlog, graph.l0, write_failure,
    array_myers, and csvcol_test are `eq`; `eq_test`'s `member` is `any_eq`;
    `lists_test` gains `test_index_of` and `test_any_eq` at strings, ints,
    data, and bool
  - `tests/io/libdoc/index.txt` re-pinned; the repo's `l0-code` skill says
    where `any_eq` lives now
  - both suites green (63, 110), fixpoint holds at the same size, seed
    refreshed. No Linux run: the runtime and the emitter are unchanged
  - next: the queue is empty. 0041's later candidates, each waiting for
    its own program: a specified `hash` with a library map (the four hash
    tries), `compare`, and function values
