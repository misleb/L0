# 0025: Updating an array held inside another without copying it

Kind: language
Status: proposed
Needs: 0024

## Why

From [0021](0021-arrays-route.md)'s prototype, `0021/bench/scratch/grid.l0`:
in an `(array (array int))`, `array_get` must give the row a reference of its
own, so the row is shared with the grid when `array_set` updates it, and
every update of a cell copies its row: 10,000 row copies for 10,000 updates.
The workaround swaps a placeholder into the slot, updates the row, and sets
it back, which leaves only the first-touch copies.

The natural fix is a builtin that takes an element out and leaves something
in its place, but it has to return both the element and the array, and
without type parameters there is no pair type to return them in. Other
shapes to weigh: an `array_swap` returning the old element while the
program keeps using the array under 0023's rule, or a two-level
`array_set2`. Not ready: it needs a program that the workaround makes too
hard, not a benchmark.

## Done when

A program that needs it, then the l0-bootstrap checklist.

## Log

- 2026-09-25: opened from 0021's finding.
