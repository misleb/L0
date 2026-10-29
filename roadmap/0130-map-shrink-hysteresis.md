# 0130: a map shrinks well below where it grows

Kind: language
Status: queued, waiting on a choice: hysteresis breaks spec 6.9
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
- 2026-10-29: research (a read-only agent; checked here). Today
  `map_cap n 8` (`lib/prelude.l0`) gives the least power of two from 8 at
  least 2n, and `map_sized` resizes to it after every put and remove, so
  the table doubles past 2^k and halves back at once. `eq`, `hash`, and
  `compare` see a map field by field, marks, slots, count, with no special
  case: they agree on maps of the same entries only because capacity and
  each slot depend on the entries alone, which spec 6.9 promises ("Where
  each entry lies in its table, and how large the table is, depend only on
  which entries it holds"), and `map_keys`'s order rests on it too. So
  hysteresis, or a `map_reserve`, breaks 6.9: in a scratch build that
  halved below an eighth full, keys 0 to 5 built up came to 16 slots and
  built to 40 and removed back to 32, `map_eq` true but `eq`, `hash`,
  `compare`, and `map_keys` all differing. A capacity that is a function
  of the count alone is a step function, and thrashes at its steps. Two
  paths that are correct: (a) keep 6.9 and replace the flat table with a
  structure whose shape depends only on its keys, a CHAMP-style trie,
  O(log32 n) puts and removes with no rehash ever, O(log n) lookups, about
  250 prelude lines rewritten and a bootstrap; (b) give up 6.9's promise,
  so a map that has shrunk is no longer `eq` to one built directly, and
  `lib/examples.l0`'s `same_elements` lesson goes. Measured, 1,000 rounds
  of one put and one remove: at 65,536 keys 6.4 ms a round today against
  3.9 us with hysteresis; at 60,000, 97 ns against 66 ns. Pins:
  `tests/unit/map_test.l0`'s `test_key_removed`, `test_grown_and_shrunk`,
  `test_as_key`, `test_scrambled_against_rebuilt` fail under (b). Next:
  the user's choice of (a), (b), or leaving it.
- 2026-10-29: left queued by the user's choice. If taken up, path (a),
  the trie, keeps every promise; (b) needs spec 6.9 changed first.
