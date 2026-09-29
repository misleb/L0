# maze

Length of a shortest path through a maze, by breadth-first search.

```
tools/l0 build maze.l0 main.l0 -o maze
./maze FILE [flat|rows|swap]
```

FILE: `#` wall, `.` open, `S` start, `E` end (each exactly once), one row
per line, same width (blank lines and `\r` ignored). Moves are up, down,
left, right, not off the edge. Prints the number of moves, or `no path`.
Exit status 1 with a message for a missing file or a malformed maze.

Modes:

- `flat` (default): cells, distances, and the queue are each one
  `(array int)` indexed by `y * w + x`. 0 copies.
- `rows`: cells and distances as `(array (array int))`, updated the natural
  way, `(array_set g y (array_set (array_get g y) x v))`. Copies a whole row
  on every distance update.
- `swap`: rows, with 0021's workaround: put an empty placeholder in the
  row's slot, update the row alone, set it back. 0 copies.

## Status

Works. `tools/l0 test maze.l0 maze_test.l0`: 14 tests pass under
`L0_RC_CHECK`, including a property test on 150 random mazes that the three
modes agree with each other and with an independent level-by-level search
over lists. All modes match `maze.py solve` on 101 to 2001, and on a 501
maze with its start walled in.

## Measurements

`maze.py gen N N 7` (a randomized depth-first maze with 5% of inner walls
removed, so there are many paths), warm binary:

| N | flat | swap | rows | Python (deque, flat list) |
| --- | --- | --- | --- | --- |
| 501 | 0.01 s, 9.7 MB | 0.02 s, 9.7 MB | 0.03 s, 11.6 MB | 0.06 s, 21.6 MB |
| 1001 | 0.04 s, 33 MB | 0.07 s, 41 MB | 0.15 s, 49 MB | 0.17 s, 41 MB |
| 2001 | 0.15 s, 127 MB | 0.36 s, 159 MB | 1.16 s, 191 MB | 0.63 s, 118 MB |

At 2001, rows copies 2,099,406 rows, 4,200,911,406 words; flat does
16.4M sets in place and swap 24.6M (three per update), none copied.
A perfect maze (`gen 2001 2001 8 0`, path length 267,712): flat 0.11 s,
swap 0.22 s, Python 0.32 s.

The 127 MB peak is all reading and allocating: a maze with S beside E peaks
the same. Cells, distances, and queue are 32 MB each (8 bytes a cell), plus
the reader's last doubling. Build: 0.40 s. Tests: 1.1 s.

rows is only 7.7 times slower than flat because a 16 KB row stays in cache;
the cost is linear in the width per update, so it grows with the maze.
