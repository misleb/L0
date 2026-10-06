# 0054: tooling: the compiler and the suite use the library's map

Kind: tooling
Status: done, changelog "The compiler and the suite keep their tables in
the library's map, and no language change for it"
Needs: 0053

## Why

[0051](0051-hash-and-map.md): the compiler's `PadMap`, with its own
`sym_hash` (about 50 lines of `compiler/emit.l0`), and
`tests/io/array_paths/graph.l0`'s `NameMap`, with `name_hash`, are each a
hash table written for one key type, which `(Map K V)` (0053) replaces.

## Done when

- `compiler/emit.l0` keeps its pad table in a `Map`, and `sym_hash` and
  `PadMap` are gone; the compiler's output is unchanged, checked as 0047
  did, against the seed it replaces, on its own source and every test
  program
- `graph.l0` uses a `Map`, and its tests pass unchanged
- both suites green, the fixpoint holds, the seed refreshed, and the
  changelog says what moved
- `roadmap/0051/` deleted

## Log

- 2026-10-06: queued by 0051.
- 2026-10-06: done.
  - `compiler/emit.l0`: the pad table is a `(Map (list int) Pad)`;
    `PadMap`, `sym_hash`, `pm_add`, `pm_bucket`, `pad_in`, and
    `read_only_in` are gone, and `pad_map`, `pad_of`, and `read_only_of`
    are three short functions over the map. The type is written out where
    `PadMap` was named, eleven places
  - `tests/io/array_paths/graph.l0`: `Named`, `NameMap`, `name_hash`,
    `nm_get`, `bucket_find`, and `nm_add` are gone; the graph holds a
    `(Map (list int) int)`. `array_paths.sh`'s check that no array copies
    now covers the map's arrays, and passes
  - equivalence: `build/stage1.ll` (the 0053 seed compiling the new
    source) equals `build/stage2.ll`, and the two compilers give identical
    output on all 90 programs in `tests/check`, `tests/lang`, and
    `tests/io`; self-compile 0.17 s against 0.16 s for the old compiler
  - both suites green (63, 115); fixpoint at 1,218,590 bytes; seed
    refreshed and reproduces itself; `roadmap/0051/` deleted
  - next: nothing queued. Left from 0051: a persistent map, when code
    keeps old versions, and an ordered one with `compare`. Left from 0049:
    typed failures for reads, closes, flushes, and renames. Owed: the
    Linux runs of 0045 and 0052
