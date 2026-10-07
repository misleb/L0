# 0059: research: ordering a value of any type, by `compare` or by function values

Kind: research
Status: proposed
Needs: nothing

## Why

[0055](0055-programs-round-three.md)'s structures worker could not write a
heap or a balanced tree once for every element type:

```
(def (smaller T) ((a T) (b T)) T
  (if (lt a b) a b))
```

```
$ tools/l0 check tmp/0055/structures/limits/01-order-type-param.l0
tmp/0055/structures/limits/01-order-type-param.l0:9:7: error: an argument of lt must be int, but this is T
```

Passing the order instead fails too (`limits/02`): `error: int_less is a
function, and L0 has no function values`. The named workaround orders a
closed sum `Key = KInt int | KStr bytes`, which costs 5.2 times on the heap
and 1.2 on the set, and admits no record as an element. The numbers worker
passed operations as int codes for want of function values. A persistent
ordered map, which 0055's editor wrote by hand as a 185-line AVL tree,
needs one or the other.

## The question

Which comes first, and at what cost to the properties the `l0-bootstrap`
skill lists? Weigh at least:

- a structural `compare` builtin on any type, as `eq` and `hash` are, with
  its order specified: what it does on lists, bytes, arrays, and data
  values, and whether a structural order is the one programs want (0041
  found most orders written here are not structural)
- a function type and function values: syntax, checking, and what a
  function value is in memory, given reference counting, tail calls, and
  padded arities (spec 8, 10)
- both, and which one the other would later make redundant
- the code here that each would change, counted: 0055's heap, set, and
  editor; the compiler's own sorts and orders; the library's helpers

## Done when

- the Log has a finding: each candidate's semantics, implementation, and
  cost, with 0055's programs rewritten against each in a prototype where
  that can be done without the feature
- a recommendation that names the first language item, with a program from
  this repository as its Why, and the items after it in order

## Log

- 2026-10-06: opened by 0055, with the user's agreement.
