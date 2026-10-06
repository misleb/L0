# 0054: tooling: the compiler and the suite use the library's map

Kind: tooling
Status: queued
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
