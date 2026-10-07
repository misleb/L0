# 0055 structures: generic heap and ordered set, LRU cache, editor with undo

Written from `lib/AGENTS.md`, `lib/skills/l0-code/SKILL.md`, the spec
(`tools/l0 spec --path`, which prints `spec/L0.md`; `lib/L0.md` differs from
it by one sentence in 6.9), `tools/l0 doc` and `tools/l0 doc NAME`, and
`lib/examples.l0` / `lib/examples_test.l0`. The library's Map source
(`lib/prelude.l0`, lines 97-253) was read after measuring limit 03, to find
its cause. No compiler, runtime, stage0, or test-suite source was read.

## Layout

```
common/tree.l0 (+ _test)     persistent AVL tree with heights and sizes, (Tree T):
                             balancing, join, and sequence-by-position ops, once for every T
kmerge/key.l0 (+ _test)      WORKAROUND: Key = KInt int | KStr bytes, and its order
kmerge/heap.l0 (+ _test)     binary min-heap, (Heap T) payloads ordered by Key
kmerge/oset.l0 (+ _test)     ordered set: (Tree Key) descent; balancing from tree.l0
kmerge/heap_int.l0           the heap copied for int keys, only to price the workaround
kmerge/oset_int.l0           the set copied for int, likewise
kmerge/kmerge.l0 (+ _test)   merge k sorted files / distinct lines in order / benches
kmerge/main.l0, gen_kmerge.py, ref_kmerge.py
lru/lru.l0 (+ _test)         LRU cache (Lru K V) over the library's Map
lru/main.l0, gen_trace.py, ref_lru.py
editor/editor.l0 (+ _test)   line buffer (Tree bytes), undo/redo stacks of versions
editor/main.l0, gen_edits.py, ref_editor.py
limits/NN-*.l0               smallest programs showing each limit
hypothetical/                what would have been written
data/                        generated inputs and outputs (123 MB; delete when done)
```

Build and test (each from the repository root):

```
tools/l0 test common/tree.l0 kmerge/{key,heap,heap_int,oset,oset_int,kmerge}.l0 kmerge/*_test.l0 common/tree_test.l0   # 29 pass
tools/l0 test lru/lru.l0 lru/lru_test.l0                                                                            # 9 pass
tools/l0 test common/tree.l0 editor/editor.l0 editor/editor_test.l0                                                 # 9 pass
tools/l0 build common/tree.l0 kmerge/{key,heap,heap_int,oset,oset_int,kmerge,main}.l0 -o kmerge/kmerge
tools/l0 build lru/lru.l0 lru/main.l0 -o lru/lru
tools/l0 build common/tree.l0 editor/editor.l0 editor/main.l0 -o editor/editor
```

(paths relative to `tmp/0055/structures/`). Every L0 output below was
compared byte for byte (`cmp`) with the reference's, and matched.

## Results

User time from `/usr/bin/time -l` (wall time was noisy, with other workers on
the machine), peak RSS. Sizes are `wc -l` of the program's L0 files, comments
included, tests and the two int-only measurement copies excluded, counting
the shared `tree.l0` (185) in each program that uses it.

| program, input | L0 lines | L0 time | L0 RSS | reference | ref time | ref RSS |
| --- | --- | --- | --- | --- | --- | --- |
| kmerge merge, 10 files x 100k words | 558 | 0.38 s | 2.4 MB | Python heapq.merge (62 lines) | 0.30 s | 17 MB |
| | | | | `sort -m` | 0.12 s | 1.4 MB |
| kmerge merge -n, 10 x 100k ints | | 0.29 s | 2.4 MB | Python heapq.merge | 0.34 s | 17 MB |
| kmerge distinct, 1M words (300k distinct) | | 1.22 s | 57 MB | Python set + sorted | 0.28 s | 46 MB |
| | | | | `sort -u` | 0.38 s | 88 MB |
| kmerge distinct -n, 1M ints | | 0.91 s | 71 MB | Python set + sorted | 0.25 s | 62 MB |
| heap: 1M random push, 1M pop, Key heap | | 1.25 s | 61 MB | Python heapq of (v, i) | 2.46 s | 162 MB |
| heap: same, int-key copy (heap_int.l0) | | 0.24 s | 35 MB | | | |
| set: 1M random insert, 500k remove, Key | | 1.64 s | 137 MB | Python set (hash, unordered) | 0.30 s | 154 MB |
| set: same, int copy (oset_int.l0) | | 1.38 s | 114 MB | | | |
| lru, cap 10,000, 1M Zipf(0.9) int keys | 181 | 1.16 s | 6.5 MB | Python OrderedDict (29 lines) | 0.18 s | 20 MB |
| lru, same, with map_remove fixed (limit 03) | | 0.23 s | 5.4 MB | | | |
| lru -s, same trace, bytes keys | | 1.37 s | 5.6 MB | Python OrderedDict | 0.18 s | 19 MB |
| lru -s, with map_remove fixed | | 0.34 s | 4.7 MB | | | |
| editor, 100k lines, 100k edits + print | 366 | 0.19 s | 73 MB | Python list + inverse ops (77 lines) | 0.71 s | 36 MB |

Hits/misses for the trace: 393,335 / 606,665 in both. `L0_ARRAY_STATS`: the
heaps and kmerge copy nothing (15.8M and 80.5M sets in place); the editor
and the sets use no arrays; the LRU copies 241,931 times (limit 03), and
with the fixed map_remove copies nothing (8.8M in place).

Python has no ordered set, and `sortedcontainers` is not installed, so the
set rows compare an AVL tree with a hash set and one sort; they say what an
L0 program pays for order, not that the tree is slow. The editor is faster
than Python because a persistent tree makes inserts O(log n) where
`list.insert` is O(n), and pays for it in memory: every old version is kept
(roughly 0.6 KB per edit, a path of about 17 nodes), where Python keeps one inverse operation.

## Limits, ranked by cost

### 1. Map removal copies the marks array (library bug) -- limits/03-map-remove-copies.l0

What could not be written: an LRU cache, or any sliding window, over the
library's Map at the library's promised "amortized constant time" removal.

`lib/prelude.l0` line 238, in `map_shift`:

```
(map_shift (array_set ms i mj) (array_set ks i (array_get ks j))
           (array_set vs i (array_get vs j)) n j (map_next j ms))
```

The last operand reads `ms` after the first operand's `array_set`, so that
update copies the whole marks array, which is spec 6.5's first copying case
and the skill's first warning. Every removal that shifts an entry back
copies the table. Measured with a map threaded through one name and nothing
else holding it:

- limits/03 (window of 10,000 keys, 1M put+remove): 436,627 copies,
  14.3e9 words copied, 1.91 s; with the reads bound first
  (`hypothetical/map_remove_fixed.l0`, a measurement copy that shadows the
  prelude's three functions): 0 copies, 0.05 s, **38x**
- lru: 241,931 copies of a 32,768-word array, 7.9e9 words; 1.16 s against
  0.23 s fixed, **5x** (bytes keys 1.37 s against 0.34 s, 4x). Fixed, L0 is
  within 1.3x of OrderedDict at a quarter of its memory

Fix: in `map_shift`, `(let nj (map_next j ms) ...)` and bind `(array_get ks
j)`, `(array_get vs j)` before the updates. The fixed copy passes lru's
tests under the reference-count check. Not worked around in `lru/lru.l0`,
which uses the library's Map as asked. Since the library's own author fell
into the trap the skill warns of, a diagnostic for it (an `array_set` whose
array variable is read by a later operand of the same call) may be worth
more than the warning.

### 2. No order on a type parameter, and no function values -- limits/01, limits/02

What could not be written: `(Heap T)` and an ordered `(Tree T)` set whose
order is T's, written once. `(lt a b)` on two T's:

```
limits/01-order-type-param.l0:9:7: error: an argument of lt must be int, but this is T
```

Passing the order instead:

```
limits/02-function-value.l0:15:16: error: int_less is a function, and L0 has no function values
```

Tried: everything that does not need the order is generic (tree.l0's
balancing, join, and every sequence operation, used at `int`, strings,
`bytes`, and `Key`; the heap's payload). Workaround (named, `kmerge/key.l0`):
the order is written once over a closed sum `Key = KInt int | KStr bytes`,
and every element is boxed into a Key on the way in. Its costs:

- heap, 1M push/pop: 1.25 s and 61 MB against 0.24 s and 35 MB for the same
  heap with int keys, **5.2x** time (a match and two reference-count pairs
  per comparison, and a block per element)
- set, 1M insert/500k remove: 1.64 s / 137 MB against 1.38 s / 114 MB,
  1.2x (allocation of tree nodes dominates)
- closed: a record type, or a pair (line, file) ordered by both, cannot be
  an element without adding a case to Key and to key_cmp; and getting int
  speed back means a copy of the structure per type (heap_int.l0, 66 lines;
  oset_int.l0, 43)

Would have written: `hypothetical/heap_compare.l0` and `oset_compare.l0`
with a builtin `compare` on any type (structural, defined by the spec as
`eq` and `hash` are), which removes Key entirely; and `hypothetical/heap_fn.l0`
with a function type `(fn T T bool)` for orders that are not structural
(descending, by one field, ignoring case). `compare` alone would have served
all three programs here; function values are the more general answer. Both
fail to check as expected (`unknown function compare`; `expected list,
array, or a data type name after ( in a type`).

Iteration order is the same limit seen from Map: `map_keys` lists in table
order, and the prelude's comment says to "sort the keys if the order
matters", which cannot be done for a generic K.

### 3. Keeping an old version copies arrays and Maps whole -- limits/04-old-versions-copy.l0

What could not be written: an editor whose buffer is an `(array bytes)` or
a Map, with undo keeping old versions. Each `array_set`/`map_put` with the
previous version on the undo list copies every entry, as the docs say:

- array of 100,000: 50.6 us and 800 KB per edit, so 100k edits would take
  about 5 s and 80 GB
- Map of 100,000: 204 us and 2 MB per edit (it copies its 262,144-entry
  values array), so 100k edits would take about 20 s and 200 GB

Not a blocker: L0 can express a persistent structure, and `common/tree.l0`
(185 lines) is one; the editor runs 100k edits in 0.19 s and 73 MB. The cost
is that the library has no persistent sequence or map, so every program
that keeps versions writes ~200 lines of AVL. A persistent ordered map over
any K needs limit 2's compare; a persistent hash map (a trie over `hash`
with `eq`) could be written generically today.

### 4. No empty (array T) without a T -- limits/05-empty-array-of-T.l0

What could not be written: an empty heap or cache holding an empty `(array
T)`. `(array_new 0 x)` needs an `x`, and a generic function has none until
given one; the version that type checks dies with `l0: runtime error: head
of empty list`. Workaround, as the library's Map does: an extra empty
constructor (`HeapEmpty`, `IHeapEmpty`, `LruEmpty`), arrays made on the
first push, and one more arm in every operation and result type (`PopNone`,
`Got (None)`). Cost is code, not time: about one constructor and one match
arm per function.

### Not limits

- pairs: a two-field `data` declaration was enough everywhere (`MinSplit`,
  `Built`, `Got`, `Step`, `Tally`); the heap keeps keys and payloads in two
  parallel arrays rather than an array of pairs, which costs nothing
- removal: works in the tree (`set_remove`, `seq_delete`) and the Map (at
  the cost in limit 1)
- `seq_get` at a T returns `Option T`, since nothing else can be returned
  for an index past the end; fine

## Documentation notes

- `lib/prelude.l0` `map_shift`: the copying bug above; `map_remove`'s doc
  "Amortized constant time" is false until it is fixed
- `l0 spec --path` prints `spec/L0.md` in this repository, while
  `lib/L0.md`, which the task named as the shipped spec, lacks 6.9's last
  sentence ("The standard library's map is such a table")
- the prelude's comment above `map_keys`, "sort the keys if the order
  matters", cannot be followed at a type parameter, and at a concrete type
  only with a comparison written by hand; the doc could say so
- `l0 check` accepts files with no `main` (as `#nomain`); AGENTS.md and the
  skill only show it with `main.l0`, so it was a pleasant surprise that a
  library file checks alone
- the skill's rule that a variable read in a later operand copies (6.5) was
  exactly right and the reason the heaps were written with every read bound
  first; they copy nothing
