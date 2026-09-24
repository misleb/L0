# paths: shortest distances in a weighted directed graph

**Status: done, with a named workaround** for the missing indexed table.

```sh
tools/l0 build programs/paths/paths.l0 programs/paths/main.l0 -o paths
./paths < input      # lines "FROM TO WEIGHT" are edges, "FROM TO" are queries
tools/l0 test programs/paths/paths.l0 programs/paths/paths_test.l0
```

Nodes are any names without spaces. A query prints the shortest distance over
the edges read before it, or `unreachable`. Weights are whole numbers of at
most 12 digits, so that a path through 100,000 edges still fits in an int. A
malformed line is reported with its line number, and ends the program with
exit status 1. `main` streams, reading one line at a time.

The algorithm is Dijkstra with a leftist heap, stopping when the target is
popped. A persistent heap has no decrease-key, so a node is pushed again
whenever its distance improves, and stale entries are skipped as they
surface.

## Files

- `paths.l0`: the tries, graph, heap, Dijkstra, and line parsing (249 lines)
- `main.l0`: the entry point (43 lines)
- `paths_test.l0`: 17 tests
- `gen_graph.py`: a random graph and queries, or their answers from Python's
  heapq

## Results

- `tools/l0 test`: 17 passed, 0 failed. The tests cover the trie (5,000
  dense keys read back), name buckets with forced collisions, heap order over
  2,000 random pushes, field and weight parsing, and hand-checked graphs
  (diamond, direction, cycles with zero weights, parallel edges, a
  20,000-edge chain). A property test checks Dijkstra against a separately
  written Bellman-Ford on 150 random 8-node graphs, all 64 pairs each.
- Every test also passes under `L0_RC_CHECK` with no runtime report.
- Mutation check: turning the heap into a max-heap fails 4 tests.

Measured with 10,000 nodes and 100,000 edges (`gen_graph.py 10000 100000 Q 1`):

| | L0 | CPython, dict + heapq |
| --- | --- | --- |
| read 100,000 edges | 0.34 s, 15 MB peak | |
| per query | 32 ms | 10.7 ms |
| 100 queries, total | 3.5 s, 18 MB peak | |

All 100 answers are identical to the Python reference
(`gen_graph.py ... --answers`).

## What L0 cost here

- **Limit 01, the main cost.** There is no array, so `dist[node]` and
  `edges[node]` are persistent binary tries keyed by the node id's bits. Each
  lookup walks about 14 levels, and each update allocates 14 new nodes.
  - Limit 01 measures a trie read at 140 ns and a read-modify-write at
    470 ns, where an array index would be a single load.
  - A profile of query answering puts 61% of the time in `l0_inc` and
    `l0_dec` and 12% in `l0_data_get`. Walking a trie counts every node it
    passes, even only to read it. This is why a native program is three
    times slower than CPython.
- **Limit 03**: no type parameters, so the trie is written three times:
  `IntMap` (distances), `EdgeMap` (adjacency), and `NameMap` (the name table,
  keyed by a hash of the name). Two copies, about 50 of the file's 249 lines,
  are redundant. `main.l0` also needs `count_fields`, a copy of `length` for
  a list of strings.
- No bitwise operations shaped the trie. A Patricia trie or a HAMT needs
  shifts, masks, and a population count, so the trie branches on `mod 2` and
  `div 2`, which is simple and costs about 4% of a query. This was not worth
  a limit of its own.
- The name table needs a hash map, which L0 does not have (limit 01 again),
  and a hash, which was easy with `mul` and `mod`.
