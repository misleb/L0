# dijkstra: shortest paths with a binary heap in an array

**Status: works.** 12 tests pass; all 100 answers on 0014's graph match
Python; no array update copies. Same input and output as 0014's `paths`.

```sh
tools/l0 build dijkstra.l0 main.l0 -o dijkstra
./dijkstra < input     # "FROM TO WEIGHT" edges, "FROM TO" queries
tools/l0 test dijkstra.l0 dijkstra_test.l0
G=roadmap/0014/data-structures/paths/gen_graph.py
python3 $G 10000 100000 100 1 > input; python3 $G 10000 100000 100 1 --answers > want
python3 py_paths.py < input        # the same input answered with dict + heapq
```

Names are any words without spaces. A query writes the shortest distance
over the edges read before it, or `unreachable`. A malformed line is
reported with its number and exit status 1. `main` streams a line at a time.

## How

- **Names**: a hash table in arrays, open addressing with linear probing,
  doubling at half full: `(data Names (Names (array (list int)) (array int) int))`.
- **Edges**: three growable int arrays (from, to, weight). The first query
  after new edges turns them into compressed rows (CSR) by counting sort:
  start offsets, targets, weights. With 0014's input that happens once.
- **Heap**: a binary min-heap whose entry k is at 2k and 2k+1 of one
  `(array int)`: distance, node. `heap_push` and `heap_pop` return only the
  array, since the caller knows the new size. No decrease-key: a node is
  pushed again when its distance improves, and stale entries are skipped.
- **Search**: `dist` is a fresh `(array int)` per query; `search` and `relax`
  thread `dist`, the heap, and its size through tail calls.

## Tests (`tools/l0 test dijkstra.l0 dijkstra_test.l0`: 12 passed)

Diamond, self and unknown names, edges arriving after a query (the rows are
rebuilt), zero-weight cycles, parallel edges, malformed lines, blank lines
and tabs; the heap draining 3,000 random pushes in order; 5,000 names through
four doublings; interning twice; a 20,000-edge chain; and a property test
against Bellman-Ford over the same edges, written separately, on 150 random
graphs, every pair. Mutation check: turning `sift_up` into a max-heap fails
4 tests.

## Measurements

0014's graph: 10,000 nodes, 100,000 edges, 100 queries (`gen_graph.py 10000
100000 100 1`). Per query is (total − edges only) / 100. Every program was
measured here, today, on the same machine, best of 2 to 3 after a warm-up:

| | edges only | total | per query | peak |
| --- | --- | --- | --- | --- |
| **L0, binary heap in an array (this)** | 0.10 s | 0.245 s | **1.45 ms** | 9.6 MB |
| L0, arrays and leftist heap (`tests/io/array_paths`) | 0.11 s | 0.58 s | 4.7 ms | 15 MB |
| L0, tries and leftist heap (0014 `paths`) | 0.13 s | 1.34 s | 12.1 ms | 17 MB |
| Python 3.14, dict + heapq (`py_paths.py`) | 0.08 s | 1.21 s | 11.3 ms | 32 MB |

The earlier figures, 31.3 ms for 0014 and about 9 ms for array_paths, were
taken before; on this machine now they are 12.1 and 4.7 ms. Against the same
day's numbers this version is 8 times faster than 0014's, 3.2 times faster
than array_paths, and 7.8 times faster than CPython per query.

- `L0_ARRAY_STATS=1`: 0 copies, 44,982,222 updates in place.
- Build: `tools/l0 build` 0.36 s.
- With the first `heap_pop` written (limit 03), the program gave the same
  answers and passed every test, but took 2.45 s: 23.5 ms per query, slower
  than 0014's tries, with 16 billion words copied.

## Arrays inside data values, and pairs

- `Graph` holds `Names` (two arrays), three edge arrays, and `Csr` (three
  arrays): arrays two levels deep in data values. None copies, because every
  function that updates one takes the value apart with `match` as its last
  use. The cost is the rebuild: `ready` names all six fields of `Graph` and
  four of `Csr` to change one.
- `Interned` (a table and an id) and `Stepped` (a graph and output) exist
  only to return two things.
- The heap layout is the workaround for the missing pair type (limit 02):
  1.8 times faster than two arrays in a `Heap` data value, 2.6 times faster
  than an `(array Entry)` of boxed pairs.
- Written twice for want of type parameters: `count_fields` is the prelude's
  `length` for `(list (list int))`; `grow`/`copy_ints` would need a copy for
  any other element type (limit 04).
