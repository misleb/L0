# 0130: a map shrinks well below where it grows

Kind: language
Status: queued
Needs: nothing

## Why

L0S's request 3 (its `build/l0-requests.md`, on a Pi 5, 2026-10-29):
`map_put` past a power of two doubles the table and `map_remove` back
below it halves it, each in time proportional to the count, as `l0 doc
map_put` says (`lib/prelude.l0`). A kernel's count of shared frames
moves across a boundary each time a 12,000-page buffer comes and goes,
and rehashes the whole table each way: 8,192 puts across 65,536 took
32 ms, against 7 ms for the same puts below it.

What could not be written: a map whose count moves back and forth across
a power of two in amortized constant time per change.

Asked: hysteresis (halve only well below the boundary, say a quarter
full), or a `map_reserve` that keeps a minimum capacity.

Hysteresis is the smaller change, needs no new name, and fixes every
caller. The table must still depend only on the map's entries, since
`eq`, `hash`, and `compare` see a map that way (`l0 doc Map`): check
whether the prelude's `eq` on maps compares the tables, in which case
two maps of the same entries at different capacities must still be
equal.

## Done when

- the checklist in the `l0-bootstrap` skill
- `map_remove` halves only at a quarter full, or the rule chosen; the
  doc comments of `map_put` and `map_remove` say the new bound
- a map's `eq`, `hash`, and `compare` stay those of its entries alone,
  with a test of two maps of the same entries reached by different puts
  and removes
- a test, or a measurement in the Log, of puts and removes across a power
  of two in constant time each

## Log

- 2026-10-29: opened from L0S's request 3. Next: check how `eq` and
  `hash` see a map's table, then the prelude.
