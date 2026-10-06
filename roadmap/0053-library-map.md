# 0053: the prelude has a map for every key and value type

Kind: language
Status: done, changelog "The prelude has a map for every key and value
type"
Needs: 0052

## Why

[0051](0051-hash-and-map.md)'s finding: six hand-built tables in this
repository, the compiler's `PadMap` among them, for want of one map that
works at every type, and 0014's wordfreq used a tree, 3.5 times slower than
0028's table in arrays. With `hash` (0052), the table in
`roadmap/0051/map.l0` needs nothing passed in.

## Done when

- `lib/prelude.l0` declares `(Map K V)`, an open-addressing table in arrays
  updated in place, starting from `roadmap/0051/map.l0`, with `map_put`,
  `map_get` returning an `Option`, `map_size`, removal, and a way to list
  the entries; the doc says an empty map is written `((MapEmpty K V))`,
  and that updating a map something else still holds copies it, as arrays
  do (spec 6.5)
- tests at several key types (strings, ints, data, bytes), with many
  collisions, growth, removal, and listing in a pinned order, under
  `l0 test`'s reference-count check, and a timing against
  `roadmap/0051/bench.l0`'s numbers
- `tests/io/libdoc/index.txt` re-pinned, the `l0-code` skills and
  `lib/examples.l0` show it, the changelog says why
- both suites green, the fixpoint holds, the seed refreshed, since the
  prelude is compiler source

## Log

- 2026-10-06: queued by 0051.
- 2026-10-06: done. Reasons in the changelog.
  - `lib/prelude.l0`: `(Map K V)` with `map_put`, `map_get`, `map_has`,
    `map_size`, `map_remove`, `map_keys`, and `map_values`, from
    `roadmap/0051/map.l0` with the hash taken inside, a mark of
    `(add (hash k) 1)` turned into a slot in one place (`map_slot`),
    removal by backward shift, and every helper named `map_` so none
    meets a name in the compiler, which shares the prelude's group
  - `tests/unit/map_test.l0`: 12 tests at string, int, data, bytes, and
    array keys; growth to 100,000 keys, which copying on every put would
    make far too slow; removal; 3,000 random puts and removes over 64 keys
    checked against a list model after each step; listing. The model test
    was checked by breaking `map_stays` on purpose: it reported 5,837
    disagreements, then passed again once restored
  - timing: 210 ms to put a million string keys, 322 ms to get them. The
    prototype given the builtin hash takes 217 and 293, so the library
    costs what the prototype does; 0051's faster gets came from its weak
    string hash keeping consecutive keys in consecutive slots. The builtin
    hashes the million keys in 36 ms against 49 for the L0 loop
  - `lib/examples.l0` gains `word_counts`, with a test; the shipped skill
    says to use a `Map` for anything looked up by a key; README and the
    library index updated
  - both suites green (63, 115); fixpoint at 1,223,833 bytes, up 61 KB for
    the copies of the map's generic functions, which LLVM drops from the
    compiler's binary (same size, same 0.17 s self-compile); seed
    refreshed and reproduces itself; `tools/l0` rebuilt from it passes
    the model test
  - next: 0054
