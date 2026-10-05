# 0041: research: how L0 compares values of any type

Kind: research
Status: done; `eq` compares any type (0042) first
Needs: nothing

## Why

[0038](0038-parametric-functions.md) lets a function be written once for
every element type, but such a function cannot compare its elements:

```
(def (member T) ((x T) (xs (list T))) bool
  (if (is_empty xs)
      false
      (if (eq x (head xs)) true (member x (tail xs)))))

(def main () int
  (if (member "b" (split_spaces "a b c")) 0 1))
```

```
$ tools/l0check lib/io.l0 tmp/0041/member.l0
tmp/0041/member.l0:4:11: error: an argument of eq must be int, but this is T
```

`eq` takes only `int`, and there are no function values to pass a
comparison in, so every equality test, lookup, set, map, and sort over
anything but `int` is written once per type. [0040](0040-library-list-helpers.md)
hit this directly: `list_eq` and `strs_eq` stay per type, and so do
`any_eq` and `index_of`. In the suite, kvlog's `find_key` and `remove_key`
and graph.l0's name interning are lookups by string key, and 0014's and
0028's wordfreq, kvstore, json, and sort compare or hash strings by hand.

## The question

What lets a function with type parameters compare, order, or hash its
elements, and what does each answer cost against the properties the
l0-bootstrap skill lists? Candidates to weigh, not a shortlist:

- structural builtins over any type, such as `equal`, `compare`, and
  `hash`, implemented once in the runtime by walking the representation of
  spec section 10.1
- a constraint on a type parameter that says it can be compared, with code
  chosen per type at compile time
- function values, so a comparison is passed in
- something else the evidence suggests

## Done when

- the Log has a finding: an inventory of the code in this repository that is
  per type only because it compares, with counts; each candidate's
  semantics, implementation, and cost; and a recommendation
- the recommendation names the first language item, with a program from the
  inventory as its Why, or says why none should be opened yet

## Log

- 2026-10-02: opened at the user's choice, over freeing the compiler from
  stage 0, function values, and a third program round. Two read-only
  workers launched: one inventories the evidence, one weighs the designs.
- 2026-10-02: **both reported; finding.** Claims re-checked in the main
  tree are marked (checked).
  - **Inventory.** Maintained code (lib, tests, compiler) has about 47
    equality functions (~325 lines), 2 orderings, and 9 hashing functions
    (~52 lines). The roadmap programs add about 21, 34, and 27. Each was
    classed as structural (a builtin replaces it), by one field (a lookup
    of a record by its key), or neither (prefix and substring tests,
    wordfreq's count-then-word order, sort's slices of one bytes value,
    kvstore's hash that must match a Python generator's).
    - Structural equality replaces `list_eq` (about 70 compiler calls,
      checked), `strs_eq`, `bools_eq`, `ty_eq`, `val_eq` and `json_eq`
      (36 arms with no wildcard), and the membership, position, set, and
      duplicate helpers.
    - The lookups by one field (`find_*`, `lookup_*`, kvlog's `find_key`)
      still drop their `list_eq`, but stay one function per record type
      unless the records become key-value pairs.
    - Ordering is mostly not structural. wordfreq sorts by count, then
      word, which needs a comparator or a key built for the purpose, so a
      structural `compare` alone earns little yet.
    - Hashing has the strongest structural case: one string-keyed hash
      trie is written four times (graph.l0's `NameMap`, the compiler's
      `PadMap` with the same hash, checked, and two copies in 0014 and
      0021).
    - Lists were chosen over better structures because keys were awkward
      to compare: the checker's symbol tables, `check_dups`, kvlog's live
      entries, and the generic `(Tree T)` in `tests/io/parametric_data`
      whose `insert` is written only at `int`.
  - **Representation.** A runtime walk can compare any two values, since
    cons and data blocks carry a pointer mask and data tags. The copies of
    a generic function know only whether a T is counted, so a walk that
    reads the header is the one implementation that fits them.
    - One gap: a `bytes` block and an `(array int)` block have the same
      header, `1<<40` (checked, `l0rt.ll:628` and `:1421`), so a walk
      cannot tell a byte count from a word count. One mask bit on bytes
      fixes it; every array path reads only bit 0.
    - Data blocks are zeroed past a narrower constructor's fields
      (checked, `l0rt.ll:286`), which section 10.1 does not promise.
    - Values cannot be cyclic (10.3), and a walk with an explicit
      worklist, like the free path's, uses no stack.
  - **Designs.**
    - *Constraints on type parameters* need a dictionary argument or a
      copy per type, which 0038 rejected, and say nothing while every type
      is comparable. Rejected.
    - *Function values* give up purely syntactic name resolution and need
      an exception to the tail-call guarantee. Without closures,
      comparators do not compose, so `(list (list int))` still needs its
      own. They are the answer for custom orders such as wordfreq's, later
      and separately.
    - *New `equal`, `compare`, `hash` builtins* would keep two names for
      equality, the trap 0040 chose the same names to avoid.
    - *Widening `eq` itself* changes the meaning of no program, since `eq`
      on anything but `int` was an error. It changes the compiler's output
      by one declare, since every `eq` there is on `int` and still emits
      `icmp`. Two goldens pin today's error and are re-blessed on purpose
      (`check_errors.out:52`, `check_fn_params.out:11`, checked).
  - **Spec problems found.**
    - Section 6 says lists and data values are compared "with a function
      written in L0", which cannot be done at a type parameter.
    - Nothing says how two bools are compared; `check_bool` works around
      it.
    - 10.1 leaves data-block padding unspecified.
    - The v1 changelog's reason for `eq` being int-only, that the
      representation discards the type, has mostly lapsed since blocks
      gained headers.
  - **Recommendation.** First, `eq` compares any two values of one type
    structurally, as language item
    [0042](0042-eq-any-type.md), with this item's `member` as its Why.
    Then, each earned separately:
    - a tooling item moving the library onto it, with generic `member` and
      `index_of`, and `list_eq` and `strs_eq` redundant for programs
    - a specified `hash` with a library map, earned by the four hash tries
    - `compare`, when a program wants structural order
    - function values, for orders that are not structural
