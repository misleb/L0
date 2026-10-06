# 0052: `hash` gives a value of any type a specified integer

Kind: language
Status: done, changelog "`hash` gives a value of any type a specified
integer"; Linux runs owed
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
- 2026-10-06: done. Decisions (reasons in the changelog):
  - spec 6.9 defines a value's items by one walk over its blocks, since a
    word alone does not say whether it is a pointer and a cons cell and a
    one-field data block can share a header: a list is its elements' items
    then 0, a data value its tag, its fields, and a 0 per slot a wider
    constructor has. The items fold with FNV-1a's basis and prime, then
    splitmix64's finalizer, then a shift right of one, so the result is
    never negative and its low bits are mixed
  - `@l0_hash(x, counted)`, since the runtime cannot tell an `int` from a
    pointer; the emitter passes 1 for a counted type, decided per copy of a
    generic function as `eq`'s choice is (10.2). It shares `@l0_equal`'s
    worklist, which no hash and comparison use at once
  - `hash` borrows, as `eq` does, so a parameter used only by it is
    read-only
  - tests: `tests/unit/hash_test.l0` (9 tests: values pinned from the spec
    alone, computed outside L0 from each value's listed items; equal values
    built differently, padding included, each pair checked with `eq`; a
    type parameter; never negative over 500 random values and the int
    extremes; multiples of 1024 filling most of 1024 slots), `tests/io/hash_deep`
    (a million-element list, an array of 1,000 lists, 100,000-deep nesting
    on a 1 MB stack under `L0_RC_CHECK`), `tests/io/hash_read_only` (an IR
    check: a bytes parameter used only by `hash` is read-only, and the
    call passes 1), `check_errors` gains three arity and type errors, and
    `shadow_test` a program's own `hash`. `bundle_prelude` and `emit_tail`
    re-blessed for the one new `declare`
  - one test of mine was wrong at first: a pair I meant as one value was
    `[3 3]` against `[3 0]`; `eq` beside each pair now catches that
  - both suites green (63, 114); fixpoint at 1,162,422 bytes; seed
    refreshed and reproduces itself; `tools/l0` rebuilt from it hashes as
    the spec says. The compiler and prelude use none of it
  - Linux runs owed: Docker is down, and the runtime and emitter changed
  - next: 0053
