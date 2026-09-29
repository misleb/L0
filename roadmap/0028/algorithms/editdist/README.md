# editdist: Levenshtein distance and alignment

**Status: works.** 9 tests pass; the distance matches Python on two
10,000-byte files; no array update copies.

```sh
tools/l0 build editdist.l0 main.l0 -o editdist
./editdist a.txt b.txt            # distance N
./editdist a.txt b.txt --align    # and one line of ops: M S D I
tools/l0 test editdist.l0 editdist_test.l0
python3 gen_text.py 10000 1500 3 a.txt b.txt     # related random texts
python3 gen_text.py --solve a.txt b.txt          # pure Python two-row DP
```

The alignment is a line of ops, one per step: `M` the bytes match, `S`
substitute, `D` delete a byte of the first file, `I` insert a byte of the
second.

## How

- Each file is read into an `(array int)` (a reversed list, then written
  into an array of its length from the back).
- **Distance**: two rows, `prev` and `cur`, which trade places each row, so
  both are updated in place; `last_row` returns the final row.
- **Alignment**: Hirschberg's algorithm, which needs only `last_row` run
  forwards over the top half and backwards over the bottom half, so it stays
  in linear space. `last_row` reads both ranges backwards when `fwd` is false.
- `align_full` is the textbook full table, one flat array of (n+1)(m+1)
  words, walked back from the corner; kept as the test oracle and to measure.

## Tests (`tools/l0 test editdist.l0 editdist_test.l0`: 9 passed)

Classic pairs, empty strings, equal and disjoint strings, the kitten/sitting
alignment, reading a file, the report. Property tests: 400 random pairs up to
7 bytes against the exponential definition; 200 pairs up to 60 bytes and 30
two-letter pairs up to 400 bytes checking that Hirschberg's and the full
table's scripts are both valid (applying one to the first string gives the
second, every M pairs equal bytes) and both cost exactly the distance.
Mutation check: reading `b` forwards in the backward pass fails all three
property tests.

## Measurements

Two 10,000-byte texts, distance 1,406, best of 2 after a warm-up:

| | time | peak memory |
| --- | --- | --- |
| L0, distance (two rows) | 0.48 s | 2.1 MB |
| L0, distance and Hirschberg alignment | 1.42 s | 2.6 MB |
| L0, full-table alignment (`bench/full_main.l0`) | 0.84 s | 765 MB |
| Python 3.14, two-row DP | 8.71 s | 16 MB |

- 10^8 cells in 0.48 s is 4.8 ns a cell. `L0_ARRAY_STATS=1` with `--align`:
  0 copies, 300,445,335 updates in place.
- **What the full table needs**: (n+1)(m+1) words, 10^8 words = 800 MB at
  10,000 by 10,000, and it grows with the product: 3.2 GB at 20,000. It works
  in L0 as one flat array (0.84 s). As a table of rows updated cell by cell,
  `(array_set t i (array_set (array_get t i) j x))`, it copies a row per cell:
  limit 01, 11.3 s already at 5,000 by 5,000.
- Build: `tools/l0 build` 0.35 s.

## Arrays inside data values, and pairs

None needed. Everything is threaded as parameters: `rows` and `fill` take
eight to ten each, which is long but not wrong.
