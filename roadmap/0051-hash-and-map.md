# 0051: research: how L0 gets a hash and a map

Kind: research
Status: done; a specified `hash` builtin (0052), then a library map
(0053), then its users (0054)
Needs: nothing

## Why

There is no map in the library, and none can be written once for every key
type: a map has to hash or order its keys, and a function with a type
parameter can do nothing with a `T` but keep it, pass it, and compare it
with `eq` (spec 4.1). The slot a key goes in cannot be computed:

```
; The slot a key of any type goes in, in a table of n slots: what every
; hash map needs, and what a generic one cannot compute today.
(def (slot_of K) ((key K) (n int)) int
  (mod (hash key) n))

(def main () int
  (add (slot_of "word" 64) (slot_of 42 64)))
```

```
$ tools/l0check lib/prelude.l0 lib/io.l0 tmp/0051/bucket.l0
tmp/0051/bucket.l0:4:8: error: unknown function hash
```

So every program that needs a map writes one, for its own key type:

- the same polynomial string hash seven times: `sym_hash` in
  `compiler/emit.l0`, `name_hash` in `tests/io/array_paths/graph.l0`,
  0014's paths, 0021's bench, and 0028's dijkstra, and `hash_onto` in 0014's
  kvstore and 0028's wordfreq, which also has `hash_back` over `bytes`
- a table or trie over it six times: the compiler's `PadMap`, `NameMap`
  three times, dijkstra's table in arrays with its own rehash, and
  wordfreq's, with its own
- 0014's wordfreq kept its counts in an AVL tree instead, "since L0 has no
  hash", and 0041 found the checker's symbol tables, `check_dups`, and
  kvlog's entries kept in lists for want of a map

0041 recommended "a specified `hash` with a library map, earned by the four
hash tries" and left it for later; the count has grown since. The compiler
can use a library map now that stage 0 no longer runs it (0045).

## The question

What gives L0 a map written once for every key type, and at what cost to
the properties the `l0-bootstrap` skill lists? Weigh at least:

- `hash` as a builtin over any type, walking a value from its block
  headers as `eq`'s `l0_equal` does (spec 6.8, 10.1), against hashing
  written in L0 per key type, against an ordering (`compare`) and a tree
- whether `hash`'s result is specified, the same on every host and every
  run, so a hash can be stored, as kvstore's file format needs, or only
  promised to agree with `eq` within one run; and what either means for
  spec 10.4
- what a map in the library looks like: a persistent trie or tree of data
  values, against arrays updated in place (spec 6.5), against both; its
  interface (`map_get` returning `Option`, `map_put`, removal, listing in
  some order), and its cost in time and memory against the copies above
- whether anything else must change first, such as bytes and arrays as
  keys, or a pair type for listing entries
- which code here moves onto it, counted: the compiler's `PadMap` and
  symbol tables, the suite's programs, and the roadmap's

## Done when

- the Log has a finding: each candidate's semantics, implementation, and
  cost, measured where it can be against the hand-written tables above
- a recommendation that names the first language item, with a program from
  this repository as its Why, and the items after it in order

## Log

- 2026-10-06: opened at the user's choice, over a third program round,
  `compare`, and function values. The program in the Why is
  `tmp/0051/bucket.l0`, quoted in full above.
- 2026-10-06: **finding.** Prototypes in `roadmap/0051/`: `map.l0`,
  `map_test.l0` (5 tests, passing under `l0 test`'s reference-count check),
  and `bench.l0`. A hash builtin does not exist, so they take each key's
  hash from the caller; the rest is generic over `K` and `V`.
  - **The hash has to be a builtin.** A function with type parameters can
    keep, pass, and `eq` a `T`, nothing more (spec 4.1), so no L0 function
    can hash a value of any type, and a hash per key type is the copy the
    Why counts seven times. `eq`'s `l0_equal` (`runtime/l0rt.ll:2103`)
    already walks any value from its block headers (spec 10.1) with a
    worklist and no recursion; a `hash` walks the same words and folds
    them instead of comparing them. It must agree with `eq`: equal values,
    equal hashes, which holds if it reads exactly what `eq` reads, contents
    and never addresses, since words past a narrower constructor's fields
    are 0 (10.1). An ordering instead (`compare`, a tree) is not earned:
    0041 found the orders written here are mostly not structural, and a
    tree is what 0014's wordfreq used and 0028's beat by 3.5 times
  - **The hash should be specified,** exactly, in the spec, as `div` and
    `mod` are. Spec 10.4 already forbids output that depends on anything
    but the input, and a map lists its keys in slot order, which is the
    hash's: if the hash were the implementation's choice, the same program
    could print in a different order on another compiler. Specified, a
    test can pin a hash, and a file can store one. The cost is that
    changing it is a language change; no stored hashes exist here yet.
    kvstore's file format used its own hash to match a Python generator,
    so that is not evidence either way
  - **The map is a table in arrays, updated in place.** Measured with
    `bench.l0` on string keys, putting all then getting all:

    | keys | table in arrays, put / get | persistent trie, put / get |
    | --- | --- | --- |
    | 200,000 | 89 / 47 ms | 61 / 96 ms |
    | 1,000,000 | 268 / 128 ms | 742 / 1140 ms |

    The table scales linearly, so every put really is in place (spec
    6.5's rule for an array that is a field of a data value taken apart at
    its last use); the trie, the shape of the compiler's `PadMap`, slows as
    its buckets fill. Every one of the six tables the Why counts is filled
    and then read, which is the table's case. Its cost is the arrays':
    updating a map that something else still holds copies all of it, so a
    program that keeps old versions, as a checker's scopes would, wants a
    persistent map instead. None here does yet: the checker's environments
    are lists, and small
  - **What writing it found:**
    - an empty map is written with its types, `((MapEmpty (list int)
      int))`, as `((None int))` is, since a function cannot take a type
      argument; there can be no `map_new`
    - its arrays cannot be made before the first key, since there is no
      value of an unknown type to fill them with; the first `map_put`
      makes them from its key and value
    - a key whose hash is 0 is marked 1, and the prototype's first draft
      placed it by its hash but moved it by its mark when the table grew,
      losing it; `test_map_grows` caught that. The library's version wants
      the slot from one place
    - removal is not in the prototype: linear probing needs a tombstone or
      a backward shift, and kvlog removes keys, so the library item
      decides
  - **Nothing else must come first.** `eq` and `hash` cover every type,
    arrays and bytes among them, so any value can be a key. Listing
    entries needs a key and a value together; the prototype's `(KV K V)`
    or a `map_keys` beside `map_get` would do, for the library item to
    choose
  - **What moves onto it:** the compiler's `PadMap` with `sym_hash` (about
    50 lines of `compiler/emit.l0`), and `tests/io/array_paths/graph.l0`'s
    `NameMap`. The roadmap's programs are history and stay as they are
  - **Order, given the two-step rule.** `lib/prelude.l0` is compiler
    source, so a map in it that calls `hash` needs a seed that knows
    `hash`:
    1. [0052](0052-hash-builtin.md), language: `(hash x)` on any type,
       specified, with `@l0_hash` added to the runtime interface; the
       compiler and prelude use none of it, and the seed is refreshed
    2. [0053](0053-library-map.md), language: `(Map K V)` in the prelude,
       from `roadmap/0051/map.l0`, with removal and listing; the seed is
       refreshed again, since the prelude is compiler source
    3. [0054](0054-map-users.md), tooling: `PadMap` and `NameMap` move onto
       it
    - later, each when a program needs it: a persistent map, for code
      that keeps versions; an ordered one, with `compare`
