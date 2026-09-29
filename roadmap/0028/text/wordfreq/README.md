# wordfreq, with a hash table in arrays

Prints the most frequent words of standard input with their counts, highest
count first, ties in byte order:

```
$ printf 'b a b c b a' | ./wordfreq
b 3
a 2
c 1
$ ./wordfreq 10 < text      # only the first 10
```

A word is a maximal run of ASCII letters, folded to lower case; every other
byte separates words. (0014's wordfreq also counted digits and bytes 128 and
up as word bytes; on `gen.py`'s inputs, which hold only letters and
punctuation, the two agree byte for byte.) A bad argument exits 2, a failed
read or write 1.

```
tools/l0 test  wordfreq.l0 wordfreq_test.l0
tools/l0 build wordfreq.l0 main.l0 -o wordfreq
```

## Files

- `wordfreq.l0`: the logic (266 lines): the scanner, over an `IoFile`, the
  hash table, the ranking heap, output to an `IoFile`
- `main.l0`: arguments, `(IoFile 0)` and `(IoFile 1)`, exit status
- `wordfreq_test.l0`: 15 tests
- `reference.py`: the same report in Python, with the same word rule

## How it works

- **The table** is `(Table keys counts size)`: an `(array (list int))` of
  keys, an `(array int)` of counts (0 marks an empty slot), and how many are
  full. Linear probing, a power-of-two capacity from 1,024, doubled by
  rehashing when more than half full.
- **Keys are held reversed**, as the scanner conses a word. Nothing is
  reversed while counting, only each distinct word once at the end.
- **Ranking**: the distinct words are copied out forwards into two arrays,
  words and counts, a max-heap of their indices is built in linear time, and
  the top N are popped, so the top 10 of n words costs n + 10 log n
  comparisons rather than a sort.
- **One scanner.** It reads an `IoFile`, so the tests run it on
  `open_in_bytes` and collect output with `open_out_buffer`. 0014 had to
  write the tokenizer twice (its limit 02), once over a list for tests and
  once over stdin.

## Status: done

- `tools/l0 test`: 15 of 15 pass, under the runtime's reference-count check.
  They cover ranking, ties, case, separators, the limit argument, growth to
  16,384 slots with every count checked, and a property test: on 200 random
  texts the table agrees with a naive association-list count, word by word.
- Byte-identical to `reference.py` and to 0014's wordfreq on both 10 MB
  inputs, and to `reference.py 10` for the top 10.
- `L0_RC_CHECK=1` on the wide 10 MB input reports nothing live at exit.
- `L0_ARRAY_STATS=1` on the wide input: **0 copies**, 2,978,124 updates in
  place. Every update of `keys` and `counts` is in place even though both
  arrays live inside a `Table` data value, which is matched apart and rebuilt
  for every word: matching a value nothing else holds releases it, and its
  arrays are then held once. The same holds for `Ranked`. See the report for
  what the spec and skill say about this.

## Measurements

Second of two runs (`../measure.sh`), Apple Silicon, macOS; 0014's program
rebuilt with today's compiler and measured the same way. Its README's
figures (2.13 s and 3.43 s) predate the faster compiler.

| input | distinct | wordfreq | 0014 (AVL tree) | Python `reference.py` |
|---|---|---|---|---|
| 10 MB, `gen.py 10 20000 1` | 19,997 | **0.16 s, 10.3 MB** | 0.56 s, 8.2 MB | 0.29 s, 95.3 MB |
| same, top 10 | | 0.16 s, 10.2 MB | | |
| 10 MB, `gen.py 10 500000 2` | 195,412 | **0.40 s, 54.1 MB** | 1.02 s, 68.0 MB | 0.41 s, 112.6 MB |
| same, top 10 | | 0.26 s, 54 MB | | |

Build: 0.37 s (`tools/l0 build`).

**Memory.** It streams, so memory depends on the distinct words, not the
input. On the wide input, the keys as cons cells are 1,533,971 letters at
24 bytes, 36.8 MB of the 54 MB; the table's two arrays of 524,288 slots are
8.4 MB. `limits/02-word-keys.l0` measures the keys alone: 40.2 MB as lists,
20.7 MB as one `(array int)` per word.

The first version peaked at 91.2 MB there: copying each key out reversed
while the table still held the original doubled the keys. Taking each key
out of the table as it is copied, `(array_set keys i (nil int))`, frees the
old one as `rev` walks it, and brought the peak to 54.1 MB. That is the
pattern 0025 describes for nested arrays, needed here for lists too; it is
cheap and local, so it is not reported as a limit.
