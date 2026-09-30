# wordfreq, with a hash table of bytes keys

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

- `wordfreq.l0`: the logic (292 lines): the scanner, over an `IoFile`, the
  hash table, the ranking heap, output to an `IoFile`
- `main.l0`: arguments, `(IoFile 0)` and `(IoFile 1)`, exit status
- `wordfreq_test.l0`: 15 tests
- `reference.py`: the same report in Python, with the same word rule

## How it works

- **The table** is `(Table keys counts size)`: an `(array bytes)` of keys,
  an `(array int)` of counts (0 marks an empty slot), and how many are full.
  Linear probing, a power-of-two capacity from 1,024, doubled by rehashing
  when more than half full.
- **Keys are bytes, in order**, one byte per letter, made once per distinct
  word from the list the scanner conses, which is reversed. A word being
  counted is hashed and compared against keys from its end, so it is
  reversed only when it is new. (At 0028 keys were the reversed lists
  themselves, 24 bytes a letter; see Measurements.)
- **Ranking**: the distinct words are copied out into two arrays, words and
  counts, sharing the table's keys, a max-heap of their indices is built in
  linear time, and the top N are popped, so the top 10 of n words costs
  n + 10 log n comparisons rather than a sort. Words are compared bytewise
  and written with `file_write_bytes`.
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
- `L0_ARRAY_STATS=1` on the wide input: **0 copies**, 9,024,474 updates in
  place. Every update of `keys` and `counts` is in place even though both
  arrays live inside a `Table` data value, which is matched apart and rebuilt
  for every word: matching a value nothing else holds releases it, and its
  arrays are then held once. The same holds for `Ranked`. See the report for
  what the spec and skill say about this.

## Measurements

wordfreq with bytes keys (0033): median of three runs, `/usr/bin/time -l`,
Apple Silicon, macOS. The other columns are from the second of two runs
(`../measure.sh`) at 0028: wordfreq with list keys, and 0014's program
rebuilt with the compiler of then. 0014's README's figures (2.13 s and
3.43 s) predate the faster compiler.

| input | distinct | wordfreq, bytes keys | list keys (0028) | 0014 (AVL tree) | Python `reference.py` |
|---|---|---|---|---|---|
| 10 MB, `gen.py 10 20000 1` | 19,997 | **0.14 s, 4.0 MB** | 0.16 s, 10.3 MB | 0.56 s, 8.2 MB | 0.29 s, 95.3 MB |
| same, top 10 | | 0.14 s, 4.5 MB | 0.16 s, 10.2 MB | | |
| 10 MB, `gen.py 10 500000 2` | 195,412 | **0.28 s, 25.1 MB** | 0.40 s, 54.1 MB | 1.02 s, 68.0 MB | 0.41 s, 112.6 MB |
| same, top 10 | | 0.17 s, 25.0 MB | 0.26 s, 54 MB | | |

**Memory.** It streams, so memory depends on the distinct words, not the
input. On the wide input the keys are 1,533,971 letters; as cons cells at
24 bytes they were 36.8 MB of 0028's 54.1 MB, and as bytes they are the
letters plus one small header per word. The table's two arrays of 524,288
slots are 8.4 MB. `limits/02-word-keys.l0` measures the keys alone: 40.2 MB as lists,
20.7 MB as one `(array int)` per word, and 11.1 MB as bytes (0026's
prototype).

0028's version first peaked at 91.2 MB there, because copying each key out
reversed while the table still held the original doubled the keys; taking
each key out of the table as it was copied fixed it. Keys that are held in
order need no copy, so the ranking arrays now share the table's keys.
