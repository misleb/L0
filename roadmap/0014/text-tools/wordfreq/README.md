# wordfreq

Reads text on stdin and prints each distinct word with its count, most
frequent first, ties in byte order:

```
$ printf 'b a b c b a' | wordfreq
b 3
a 2
c 1
```

A word is a maximal run of ASCII letters, ASCII digits, and bytes 128 and up,
so UTF-8 words stay whole. ASCII letters are folded to lower case; nothing
else is.

## Files

- `wordfreq.l0`: the logic: word bytes, an AVL tree of counts, merge sort,
  rendering
- `main.l0`: the streaming entry point. It is separate because `l0 test`
  supplies its own `main`.
- `wordfreq_test.l0`: 11 tests, including an AVL height check on sorted
  input and a property test of the ordering over 200 random texts
- `gen.py`: generates Zipf-distributed pseudo-prose
- `reference.py`: the same report in Python, for comparing output

```
tools/l0 build programs/wordfreq/wordfreq.l0 programs/wordfreq/main.l0 -o wordfreq
tools/l0 test  programs/wordfreq/wordfreq.l0 programs/wordfreq/wordfreq_test.l0
```

## Status: done

- `l0 test`: 11 of 11 pass.
- The output is byte-identical to `reference.py` on 50 KB, 2 MB, and both
  10 MB inputs.
- `L0_RC_CHECK=1` reports nothing live at exit on the 50 KB and 2 MB inputs
  and on empty input.

## Measurements

These use `programs/measure.sh`, which reports the second of two runs; a newly
linked binary's first run on macOS pays about 1 s for code verification.

| input | distinct words | wordfreq | peak RSS | Python `reference.py` |
|---|---|---|---|---|
| 10 MB, `gen.py 10 20000 1` | 19,997 | 2.13 s | 9.6 MB | 0.24 s |
| 10 MB, `gen.py 10 500000 2` | 195,412 | 3.43 s | 81.5 MB | 0.37 s |

Where the 2.13 s goes. Each row is a stripped-down variant run on the same
input; the variants were scratch programs and are not kept:

| variant | time |
|---|---|
| read every byte, count them | 0.04 s |
| also split into words, lowercase, `rev` each word | 0.30 s |
| also search the tree for each word, inserting only new ones | 1.14 s |
| the real program: insert every word, rebuilding its path | 2.13 s |

About 1.0 s of the 2.13 s goes to rebuilding a search path of up to 17 nodes
(the tree's height) only to add 1 to a count, and 0.84 s to searching. There are 1.35 million
words. That is limit 01.

The whole-input form of `main`, with the same logic, gives the same output in
2.32 s with a 262 MB peak for the 10 MB input, and 334 MB for the wide one. The
input list costs 24 bytes per input byte before `main` starts. Streaming is the
only reasonable choice here, as the skill says.

## Workarounds, named

- **An AVL tree instead of a hash table (limit 01).** The tree is
  `Tree`, `height`, `node`, `balance`, `rotate_left`, `rotate_right`, and
  `insert`, 62 lines with comments. It costs the 1.84 s of search and
  rebuilding measured above, against 0.24 s for the whole job in Python.
- **The tokenizer loop is written twice (limit 02).** `count_list` walks a
  string for the tests, and `scan` in `main.l0` reads stdin. They are 7 and 9
  lines and must be kept in step by hand.
- **Sorting is written for this one element type and ordering (limit 03).**
  `rev_wc_onto`, `Halves`, `deal`, `merge`, and `sort_wc` take 33 lines with
  comments, because the prelude's `rev` is `(list int)` only and there is no
  generic sort to pass `before` to.
