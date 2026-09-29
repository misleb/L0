# 0028 algorithms: Kruskal, edit distance, Dijkstra, written with arrays

All three programs work, pass their tests, beat CPython, and do every array
update in place (`L0_ARRAY_STATS=1` reports 0 copies at full size).

| program | size | L0 | Python 3.14 | earlier L0 |
| --- | --- | --- | --- | --- |
| `mst/` | 100,000 nodes, 1,000,000 edges | 0.26 s, 64 MB | 0.82 s, 217 MB | none |
| `editdist/` distance | two 10,000-byte files | 0.48 s, 2.1 MB | 8.71 s, 16 MB | none |
| `editdist/` + alignment | same | 1.42 s, 2.6 MB (Hirschberg) | | full table 0.84 s, 765 MB |
| `dijkstra/` per query | 10,000 nodes, 100,000 edges | 1.45 ms | 11.3 ms | 0014 tries 12.1 ms, array_paths 4.7 ms |

Each `tools/l0 build` takes 0.35 to 0.38 s. Every measurement is `/usr/bin/time
-l`, via `measure.sh`, with outputs in `results/`. `/usr/bin/time -l` fails
inside the agent sandbox (`sysctl kern.clockrate: Operation not permitted`),
so the measurements ran outside it. The first run of a freshly built binary
takes about 0.4 s longer on macOS, so every figure is after a warm-up run.

## Limits, ranked by cost

1. **Limit 01: updating an array inside another array copies it** (0025).
   `limits/01-nested-array-update.l0`, `hypothetical/01-nested-array-update.l0`.
   The full edit-distance table as a table of rows, filled with
   `(array_set t i (array_set (array_get t i) j x))`, copies a row per cell,
   O(n m²) words. Measured (fill an N by N table):

   | N | nested | swap-out workaround | row-wise | flat |
   | --- | --- | --- | --- | --- |
   | 3,000 | 2.04 s, 27 G words copied | 0.08 s | 0.03 s | 0.02 s |
   | 5,000 | 11.29 s, 125 G words copied | 0.23 s | 0.06 s | 0.06 s |

   At 10,000 it would be minutes against 0.84 s. `editdist` did not need it:
   the table is one flat array, and building each row whole before storing it
   also copies nothing. The named workaround, taking the row out by storing a
   placeholder in its slot, updating it alone, then putting it back, costs
   three updates per cell. So 0025 is shown, but these programs did not earn
   it, since a flat array was the better layout anyway.

2. **Limit 03: reading an array after an `array_set` of it in the same
   expression copies it, silently.** `limits/03-read-after-set.l0`,
   `hypothetical/03-read-after-set.l0`. I first wrote `heap_pop` as
   `(array_set (array_set h 0 (array_get h k)) 1 (array_get h (add k 1)))`.
   The outer `array_get` runs after the inner `array_set` consumed `h`, so
   every pop copied the heap. `dijkstra` still gave all 100 right answers
   and passed every test, but took 2.45 s instead of 0.245 s (23.5 ms per
   query, slower than 0014's tries), copying 16 billion words. The minimal
   program: 100,000 two-word moves on a 10,000-word array take 0.18 s and
   copy a billion words, against 0.01 s with the reads bound first. Only
   `L0_ARRAY_STATS` showed it. It costs the most of any limit here when hit,
   ranked second only because the fix is two `let`s once you know. The
   compiler's last-use analysis already sees the case, so it could warn;
   moving the read earlier is not allowed, since `array_get` can fail
   (spec 8).

3. **Limit 02: no pair type.** `limits/02-no-pair-heap.l0`,
   `hypothetical/02-no-pair-heap.l0`. A heap of (distance, node) pushing and
   popping 1,000,000 entries:

   | layout | time | peak |
   | --- | --- | --- |
   | flat: entry k at 2k, 2k+1 of one int array (what `dijkstra` uses; a named workaround, nothing checks the layout) | 0.27 s | 34 MB |
   | parallel: two int arrays and the size in a `Heap` data value | 0.49 s | 33 MB |
   | boxed: `(array Entry)`, `(data Entry (Entry int int))` | 0.70 s | 49 MB |

   The same gap appears as one-use data types for returning two things:
   `Found` and `UF` in `mst` (doubling the Kruskal loop, 0.02 to 0.04 s, 8% of
   the run), and `Interned`, `Stepped`, `Loaded`, `Outcome` elsewhere. None
   copies an array; the cost is a heap block per call and a declaration per
   shape.

4. **Limit 04: no type parameters.** `limits/04-no-type-parameters.l0`
   (checker: `argument 1 of grow_ints must be (array int), but this is (array
   (list int))`), `hypothetical/04-no-type-parameters.l0`. Written twice:
   `grow`/`copy` again for `(array Entry)`; `count_fields`, the prelude's
   `length` for `(list (list int))`. The name table is a map from `(list int)`
   to `int` only; another would be about 50 more lines. The sort in `mst`
   works for any int key only because it sorts indices; a record sort or a
   compound key would need a copy per element type and order, since there are
   no function values either. Cheap here, because almost everything is
   `(array int)`.

Not limits: `min`/`max` written per program, strict `and`/`or` (nested
`if`s), and eight to thirteen parameters threaded through the state machines
and DP loops. All are long, but none is wrong.

## Arrays inside arrays or data values

- `mst`: `Loaded` returns three arrays; `UF` holds parent and rank; `Found`
  holds a `UF`. 0 copies.
- `dijkstra`: `Graph` holds `Names` (two arrays), three edge arrays, and
  `Csr` (three arrays). 0 copies. The cost is rebuilding: to change one field
  you name all of them.
- `limits/02` parallel: two arrays in `Heap`. 0 copies, 1.8 times slower
  than the flat heap.
- `limits/01`: an array inside an array. It copies unless it is taken out
  first.

**An array in a data value that is taken apart by its last use updates in
place.** `match` on a subject not used later releases the block once the arm
has taken its fields (spec 10.3), so each array's count is back to 1. The
shipped skill says the opposite (below).

## What the spec and the shipped skill get wrong or leave out

- **Shipped skill, Arrays**: "an array stored inside another array or a data
  value, whose every update copies it". That is false for data values, and
  for arrays taken out of an array with the swap-out idiom. Every data-held
  array in these programs updated in place. It copies only while the outer
  value still holds it. As written, the skill steers people away from the
  `UF`/`Graph` style, which is free apart from allocation.
- **Spec 6.5** says the same thing more carefully: "since `array_get` and
  `match` give it a holder of its own while the outer value still holds it".
  But it never says that when the `match` is the outer value's last use, the
  outer value lets go, and that is the case that matters. 6.5 should say so,
  with the destructure-and-rebuild shape as an example.
- **Shipped skill**: "Reading the array in the same expression, as
  `array_get` does here, is fine." It is fine only when the read is among the
  `array_set`'s own operands, since variables are taken last (10.3). A read
  in an enclosing expression that is evaluated after the `array_set` copies
  (limit 03). The rule to state: nothing may use the array after the
  `array_set` that consumes it, in evaluation order.
- **Spec 10.3**, the bullet on `head`, `tail`, and so on: "`array_set`
  consumes its array and its element, as any function consumes its
  arguments A `match` whose subject…". There is a sentence break missing
  before "A `match`", and the `match` rule has been run into the builtin
  bullet, where it is easy to miss. It is the rule the in-place behaviour of
  data-held arrays depends on.
- **Skills, `push`**: nesting `(push a (push b acc))` pushes `b` first, so
  the chunks come out in the reverse of the order they are written. Both
  skills show only the `let` chain, which is right; a line saying that nested
  `push` reads inside out would have saved a failed test (in `mst_test.l0`).
- **Shipped skill, Testing**: `rand_next` and `rand_below` exist only under
  `l0 test`. A benchmark program that wants the same generator has to write
  its own (`limits/02`). This is minor, but worth one line.
- **0028 roadmap**: array_paths is "about 9 ms" per query and 0014 is
  "31.3 ms". On this machine today they are 4.7 ms and 12.1 ms, so any
  comparison should re-measure both rather than quote them.

## Files

```
measure.sh                          time and peak memory of one command
mst/        mst.l0 main.l0 mst_test.l0 gen_mst.py README.md
            bench/{load,sort,flat}_main.l0   phase timings, flat union-find
editdist/   editdist.l0 main.l0 editdist_test.l0 gen_text.py README.md
            bench/full_main.l0               full-table alignment
dijkstra/   dijkstra.l0 main.l0 dijkstra_test.l0 py_paths.py README.md
limits/     01-nested-array-update.l0 02-no-pair-heap.l0
            03-read-after-set.l0 04-no-type-parameters.l0
hypothetical/ the same four names: the code I would have written
data/       generated inputs; results/  every measured run's output
```
