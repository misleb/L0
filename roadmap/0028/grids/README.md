# 0028 grids: Life, maze, Sudoku written with arrays

All three programs work, pass their tests under `L0_RC_CHECK`, match a
Python reference byte for byte, and run 4 to 14 times faster than Python
in similar memory. See each directory's README.

| program | size | L0 (best mode) | Python 3.14 |
| --- | --- | --- | --- |
| life | 1000x1000, 100 gens | 0.72 s, 25.5 MB | 9.82 s, 46.5 MB |
| maze | 2001x2001 | 0.15 s, 127 MB | 0.63 s, 118 MB |
| sudoku | 99 hard, 225,578 nodes | 0.29 s, 1.6 MB | 3.08 s, 15.5 MB |

Builds take 0.4 s each. `measure.sh` records time, peak RSS, and
`L0_ARRAY_STATS` (it needs to run outside the sandbox for `time -l`).

## Limits, by cost

1. `limits/01-nested-update-copies.l0`: updating a cell of an
   `(array (array int))` copies its row. maze rows mode: 2.1M row copies,
   4.2e9 words, 1.16 s against 0.15 s flat; the placeholder-swap workaround
   costs 0.36 s. 4M updates on 2000x2000: 0.73 s against 0.10 s swapped.
   Earns 0025 if a program needs rows; flat indexing avoids it in all three.
2. `limits/02-read-only-helper-refcounts.l0`: passing an array to a helper
   that only reads it costs an inc and a dec per call. 0.27 s against 0.09 s
   for the same helper taking ints; 45% of sudoku's time (0.29 s against
   0.16 s inlined). Needs no syntax, only borrowing in spec 10.3.
3. `limits/03-no-generic-array-helpers.l0`: growing an array while reading
   needs push/copy/trim, written twice here, and only ever for one element
   type, since there are no type parameters; the library has no array
   functions.
4. `limits/04-cells-are-words.l0`: 8 bytes per byte-valued cell. 28 MB of
   maze's 127 MB. Does not earn 0026: every grid here fits, at or under
   Python's memory.
5. `limits/05-no-bit-operations.l0`: no bitwise operations; flag arrays
   (0.13 s) do the job, and emulating masks with div/mod is 17x slower.

Each has a `hypothetical/` counterpart with the code that would have been
written.

## Probes

`probes/probe.l0`, 1000 updates each:

| case | copies |
| --- | --- |
| threaded through a loop | 0 |
| in a data field, data matched at its last use, rebuilt | 0 |
| returned in a data value and matched at once | 0 |
| a row of an array of rows, via array_get | 1000 |
| the same with the placeholder swap | 9 (first touch of shared rows) |
| in a data field, data still used after the match | 1000 |

`probes/borrow/` is sudoku with the check inlined; `probes/life_inline/`
is the same for life, which gets slower (0.78 s against 0.71 s), since LLVM
already inlines `flat_neighbours` there.
