# life

Conway's Game of Life on a W by H torus.

```
tools/l0 build life.l0 main.l0 -o life
./life BOARD GENERATIONS [flat|rows|rows-reuse]
```

BOARD is a file of `.` and `#`, one row per line, every row the same width
(blank lines and `\r` ignored). Prints the board after GENERATIONS.
Exit status 1 with a message for a missing file or a malformed board, 2 for
bad arguments.

Modes:

- `flat` (default): one `(array int)` indexed by `y * w + x`, and a spare
  one each generation writes into; the two swap. 0 copies.
- `rows`: `(array (array int))`, each generation building fresh rows with
  an inner loop, storing each row once. 0 copies.
- `rows-reuse`: rows double-buffered like flat, writing into the spare
  grid's row. `array_get` leaves the grid holding that row, so its first
  `array_set` copies it: one row copy per row per generation, h * gens in
  all, which costs what `rows` spends allocating.

## Status

Works. `tools/l0 test life.l0 life_test.l0`: 19 tests pass under
`L0_RC_CHECK` (parsing and its errors, blinker, block, glider crossing every
edge of a 6 by 6 torus, and a property test that the three modes agree on 60
random boards). All three modes match `life.py` byte for byte on 200x150x50
and 1000x1000x100.

## Measurements

1,000 by 1,000 random board (30% alive), 100 generations, warm binary:

| run | time | peak RSS | array copies | sets in place |
| --- | --- | --- | --- | --- |
| L0 flat | 0.72 s | 25.5 MB | 0 | 103,047,552 |
| L0 rows | 0.91 s | 41.3 MB | 0 | 105,148,552 |
| L0 rows-reuse | 0.90 s | 57.0 MB | 100,000 (1e8 words) | 106,049,552 |
| Python 3.14, lists of lists | 9.82 s | 46.5 MB | | |

Reading and writing the board alone (0 generations): 0.02 s, 25.5 MB.
Build: 0.40 s. Tests: 1.3 s.

`life.py gen W H SEED` makes boards; `life.py run BOARD N` is the reference.

Arrays of rows cost nothing here, because each row is filled by a loop over
a fresh or taken row and stored once; a program that updates single cells
of a row-held grid is another matter (see `../maze`, `../limits/01`).
