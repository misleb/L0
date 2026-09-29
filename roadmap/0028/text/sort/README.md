# sort, bytewise

The lines of standard input in bytewise order, as `LC_ALL=C sort` prints
them. A last line without a newline gets one, as `sort` gives it.

```
tools/l0 build sort.l0 main.l0 -o sort
./sort < text
tools/l0 test sort.l0 sort_test.l0
```

## Files

- `sort.l0`: reading, line starts, merge sort, output (189 lines)
- `main.l0`: the entry point (14 lines)
- `sort_test.l0`: 10 tests
- `gen_lines.py`: writes the test input: lines of 0 to 120 bytes from a
  3,000-word vocabulary with heavy prefix sharing and repeats, about 2% with
  bytes 128 and up, 1% starting with a tab, CR, or `~`, 0.5% empty, and no
  final newline
- `reference.py`: the same in Python

## Representation and algorithm, and why

- **All bytes in one `(array int)`, lines as indices.** `starts` holds where
  each line begins plus one sentinel, so line i is `starts[i]` up to
  `starts[i+1] - 1`. The sort moves one int per line and never touches a
  byte, and a line costs 8 bytes of index. Lines as `(list int)` in an
  `(array (list int))` would cost 24 bytes a byte (250 MB for 10 MB) before
  sorting started, and would make every comparison chase pointers.
- **Bottom-up merge sort of line indices.** It is stable, which bytewise
  sorting does not need but gets for free, and makes n log n comparisons on
  any input, so no input drives it quadratic, as a naive quicksort can on
  sorted or repetitive lines. Each pass reads one index array and writes a
  fresh one in place (`array_set` on an array only the pass holds), so no
  pair of arrays has to be returned. A pass allocates one array of 171,000
  ints, 1.4 MB, which is nothing against the 10 MB it sorts.
- A comparison reads bytes from both lines by index until they differ.

## Status: done

- `tools/l0 test`: 10 of 10 pass, under the reference-count check: empty
  input, a missing final newline, empty lines, prefixes, bytes above 127,
  tab, CR and DEL, duplicates, the line index, 30,000 lines (both arrays
  grow), and a property test: on 300 random texts the output equals an
  insertion sort of the lines held as lists.
- Byte-identical to `LC_ALL=C sort` and to `reference.py` on the 10 MB input
  (171,367 lines) and on a 20 MB one.
- `L0_RC_CHECK=1` on 10 MB: nothing live at exit.
- `L0_ARRAY_STATS=1` on 10 MB: **0 copies**, 31,057,358 updates in place.

## Measurements

Second of two runs (`../measure.sh`).

| input | sort | `LC_ALL=C sort` | Python `reference.py` |
|---|---|---|---|
| 1 MB | 0.02 s, 33 MB | 0.00 s, 3.8 MB | 0.04 s, 11 MB |
| 5 MB | 0.11 s, 130 MB | 0.02 s, 12 MB | 0.07 s, 23 MB |
| **10 MB** | **0.26 s, 260 MB** | 0.04 s, 22 MB | 0.10 s, 37 MB |
| 20 MB | 0.63 s, 519 MB | 0.10 s, 41 MB | 0.21 s, 67 MB |

Build: 0.37 s.

Where the 0.30 s goes (`../exp/stage.l0`, each stage cut off after the
last): reading 0.11 s, finding lines under 0.01 s, sorting 0.14 s, writing
0.05 s.

**Memory is all input**: 257 MB of the 260 MB peak is reading 10 MB into an
array that doubles (`limits/01-input-into-array.l0`), about 25 bytes a byte.
The same program reading into 64 K chunks held in an array of arrays
(`../exp/sort_chunks.l0`, the workaround) peaks at 91.5 MB but takes 0.43 s,
since every byte read becomes two `array_get`s, a `div`, and a `mod`. Packed
bytes of exactly the input's length (0026) would make it about 10 MB plus
1.4 MB per index array.
