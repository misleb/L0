# 0025: Updating an array held inside another without copying it

Kind: language
Status: queued, by the user's choice
Needs: 0030

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

**The programs, from [0028](0028-programs-with-arrays.md):** grids' maze,
written with an array of rows updated the natural way, copies 2.1 million
rows and is 7.7 times slower than flat (`0028/grids/maze/`), and
`0028/grids/limits/01-nested-update-copies.l0` makes 4,000,000 copies in
0.65 s where the swap makes none in 0.10 s, re-checked. algorithms'
`limits/01` fills a 5,000 by 5,000 table in 11.3 s nested against 0.06 s
flat. Every worker found a flat array the better layout, so this was queued
by the user's choice rather than because no layout works.

## Done when

The shape settled first, in this item: a two-level `array_set2`, an
`array_swap` that returns the old element while the program keeps the array,
or something else, weighed against there being no pair type. Then the
l0-bootstrap checklist, with the maze's array-of-rows version making no
copies.

## Log

- 2026-09-25: opened from 0021's finding.
- 2026-09-28: queued after 0030 by the user's choice, with 0028's maze as
  its program.
