# 0051: research: how L0 gets a hash and a map

Kind: research
Status: proposed
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
