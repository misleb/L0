# 0024: Arrays

Kind: language
Status: queued
Needs: 0023

## Why

From [0014](0014-programs-round-two.md) and [0021](0021-arrays-route.md). All
three of 0014's workers lacked an indexed table, and it cost more than
anything else they hit; the checker's answer to their hypotheticals was
`expected list after ( in a type` and `unknown function array_new`. With
0021's prototype arrays and 0023's release rule, measured on the same inputs:

| | today | with arrays |
|---|---|---|
| histogram of 1 MB (`0014/text-tools/limits/01-no-array.l0`) | 1.26 s list, 0.18 s tree | 0.012 s |
| Myers at D = 10,000 (`0014/bytes-encodings/limits/03-no-arrays.l0`) | 1.37 s | 0.156 s |
| Dijkstra per query (`0014/data-structures/paths`) | 31.3 ms | 8.7 ms, CPython 10.7 |

The array programs are in `0021/bench/`.

## Done when

The l0-bootstrap checklist, plus:

- `(array T)` in section 3, and `array` reserved as `list` is
- `array_new`, `array_len`, `array_get` (borrowing its array), and
  `array_set` (consuming it) in section 6, with `array_set` stated to update
  in place exactly when nothing else holds the array, under 0023's rule
- an index out of range and a negative length as runtime errors in section 8
- the layout in section 10.1: header size 0 marks an array, a length word,
  then the elements, mask bit 0 meaning they are pointers; malloc'd and
  freed; and section 10.3's note that a count stuck at its maximum can be
  reached by `array_new` of 2^24 copies of one pointer
- the three benchmarks from `0021/bench/` as tests of behaviour, with a
  runtime check that their loops copy nothing, and the timings above
  re-measured
- the l0-code skill's performance advice for arrays: the loop shape that
  updates in place, and that a nested update copies (0025)

## Log

- 2026-09-25: opened from 0021's finding.
