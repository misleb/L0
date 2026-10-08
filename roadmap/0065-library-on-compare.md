# 0065: tooling: the library sorts and takes min and max of any type

Kind: tooling
Status: proposed
Needs: 0064

## Why

[0059](0059-compare-or-function-values.md) counted about 15 int `min` and
`max` one-liners in 13 files, and every sort here written for one element
type: 0014's and 0028's wordfreq, 0028's insertion sort of lines and its
Kruskal merge sort, and 0055's heap and set twice over. With 0064's
`compare`, each is written once. The prelude is compiler source, so its use
of `compare` waits for a seed that knows it.

## Done when

- the prelude has a generic, stable `sort` of a list by `compare`, linear
  in stack and n log n in time, and `min` and `max`; documented, tested at
  ints, strings, and a record, and the library's own int `max` callers moved
  onto it where they read better
- the examples show ordering by a key, such as count descending then word
  as `(Key (neg count) word)`; both `l0-code` skills say how, and that a
  structural order is not a numeric one for a representation such as
  0055's bignums, whose limbs run least significant first
- `map_keys`'s doc points to `sort`
- both suites green, and the seed refreshed, since the prelude changed

## Log

- 2026-10-07: proposed by 0059.
