# 0052: `hash` gives a value of any type a specified integer

Kind: language
Status: queued
Needs: 0051

## Why

[0051](0051-hash-and-map.md)'s finding. No L0 function can hash a value of
any type, since a function with type parameters can only keep, pass, and
compare a `T`:

```
(def (slot_of K) ((key K) (n int)) int
  (mod (hash key) n))

(def main () int
  (add (slot_of "word" 64) (slot_of 42 64)))
```

```
tmp/0051/bucket.l0:4:8: error: unknown function hash
```

So the repository carries the same string hash seven times (`sym_hash` in
`compiler/emit.l0`, `name_hash` in `tests/io/array_paths/graph.l0` and three
roadmap programs, `hash_onto` in two), and no map can be written once for
every key type.

## Done when

- spec 6 gains `hash`: `(hash x)` takes a value of any type and returns an
  `int`, defined exactly, from the value's contents as `eq` sees them
  (6.8), so that `(eq a b)` implies `(eq (hash a) (hash b))`; the
  definition says what each type contributes and how they are combined,
  with wrapping arithmetic, and that it is the same on every host and run
- spec 10.3 gains `@l0_hash`, which walks a value as `@l0_equal` does, with
  a worklist and no recursion, and the compiler emits `int` and `bool`
  directly where that is simpler
- tests: known hashes pinned for each kind of value, equal values built
  differently hashing alike, a long list and a deep nesting on a small
  stack, `hash` at a type parameter, and a program's own `hash` still its
  own (spec 7, 0031)
- both suites green, the fixpoint holds, the seed refreshed, the compiler
  and prelude using none of it, the changelog says why, and Linux runs, as
  the runtime changes

## Log

- 2026-10-06: queued by 0051.
