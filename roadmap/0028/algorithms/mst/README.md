# mst: Kruskal's minimum spanning tree

**Status: works.** 10 tests pass; answers match Python on 100,000 nodes and
1,000,000 edges; no array update copies.

```sh
tools/l0 build mst.l0 main.l0 -o mst
./mst edges.txt          # or ./mst < edges.txt
tools/l0 test mst.l0 mst_test.l0
python3 gen_mst.py 100000 1000000 7 > edges.txt     # connected random graph
python3 gen_mst.py --solve edges.txt                # Python's answer
```

Input is one edge `FROM TO WEIGHT` per line, whole numbers, node ids 0 to
N-1 (N is the largest id plus one). Output is the total weight and edge count
of a minimum spanning forest. A malformed line is reported with its number and
exit status 1.

## How

- **Reading**: one byte-level state machine (`rd`, `end_field`, `end_line`)
  over the file, so no line is ever built as a list. Edges go into three
  growable `(array int)`s (from, to, weight) that double when full.
- **Sorting**: a stable bottom-up merge sort of an index permutation by the
  weight array, between two arrays that trade places each pass.
- **Union-find**: by rank, with path compression in two passes (find the root,
  then point the path at it), parent and rank in two arrays held together in
  `(data UF (UF (array int) (array int)))`. `uf_find` returns
  `(Found root uf)`.

## Tests (`tools/l0 test mst.l0 mst_test.l0`: 10 passed)

Hand-checked graphs (triangle, empty, forest, self-loop and parallel edges,
blank lines and tabs, three malformed lines), the sort on a small and a
3,001-key random array (ascending and a permutation), union-find, and a
property test against Prim's algorithm over an adjacency matrix, written
separately, on 300 random connected graphs. Mutation checks: an unstable
merge (`le` for `lt`) fails the stable-order test; sorting descending fails
5 tests; accepting an edge whose ends are already joined fails 2, including
the Prim property. Dropping the rank increment fails none, rightly, since it
changes only speed.

## Measurements

100,000 nodes, 1,000,000 edges (18.6 MB), Apple Silicon, best of 3 after a
warm-up run (the first run of a fresh binary costs about 0.4 s more on macOS):

| | time | peak memory |
| --- | --- | --- |
| L0, whole program | 0.26 s | 64 MB |
| L0, reading only | 0.10 s | 48 MB |
| L0, reading and sorting | 0.22 s | 48 MB |
| L0, union-find without `UF`/`Found` blocks (`bench/flat_main.l0`) | 0.24 s | 64 MB |
| Python 3.14, `sorted` + union-find | 0.82 s | 217 MB |

- `L0_ARRAY_STATS=1`: 0 copies, 27,450,180 updates in place.
- Build: `tools/l0 build` 0.37 s.

## Arrays inside data values, and pairs

- `Loaded` returns three arrays and two ints from the reader, and `UF` holds
  parent and rank, since a union may change both. Neither copies: `match` on
  a value used for the last time releases the block once the arm has taken
  its fields, so each array's count is back to 1 before it is updated.
- `Found` exists only because `find` returns two things, a root and the
  compressed union-find. Building a `Found` and a `UF` per find doubled the
  Kruskal loop (0.02 s to 0.04 s) against the version with parent and rank as
  two parameters and the union written inline, 8% of the whole run.
- Nothing had to be written twice: every array is `(array int)`, and the sort
  is generic over any int key because it sorts indices (see limit 04).
