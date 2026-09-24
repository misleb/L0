# linediff

`linediff A B` prints the shortest edit script from file A to file B, one
line per line: `-` before a line only in A, `+` before a line only in B, and
a space before a line in both. The lines kept are a longest common
subsequence. Exit status is 0 if the files have the same lines, 1 if they
differ, and 2 on trouble (a missing file, a failed read), as with `diff`.

```sh
export L0_COMPILER=$PWD/build/l0c-native L0_RUNTIME=$PWD/build/l0rt.o
tools/l0 build programs/linediff/linediff.l0 programs/linediff/linediff_main.l0 -o /tmp/linediff
tools/l0 test programs/linediff/linediff.l0 programs/linediff/linediff_test.l0
programs/linediff/bench.sh 5000 1
```

`tools/l0 run` cannot pass arguments to a program; it takes every argument
as a source file. So a program with arguments has to be built and then run.

## Status: done

- **Tests:** 13 of 13 pass, and also pass under `L0_RC_CHECK=1`. They cover
  line splitting, empty files on either side, a changed line, the example
  from Myers' paper (distance 5), and a property over 300 random pairs of
  files of up to 40 lines from a 3-line alphabet. For each pair, the kept
  and deleted lines rebuild A, the kept and inserted lines rebuild B, and
  the distance equals |A| + |B| − 2·LCS. LCS here comes from an independent
  textbook dynamic program in the test file.
- **Measurement:** two 5,000-line files, with 1% of the second's lines
  replaced. `bench.sh` checks that the output rebuilds both files and
  compares the script's length to the system `diff`'s. Best of three,
  Apple M4 Pro:

  | changed | linediff | peak | changed lines, ours / Apple diff | Apple diff |
  | --- | --- | --- | --- | --- |
  | 1% | 0.01 s | 9.6 MB | 108 / 108 | 0.00 s |
  | 10% | 0.09 s | 29 MB | 934 / 934 | 0.01 s |
  | 50% | 2.51 s | 425 MB | 4892 / 4898 | 0.02 s |
  | 100% | 8.44 s | 596 MB | 10000 / 10000 | 0.02 s |

  At 50% our script is 6 lines shorter than Apple's: its `diff` is not
  always minimal, and this is. The 1% case, which is what was asked for, is
  as fast as the system's.

## How it works, and the workaround in it

Myers' O((N+M)D) greedy algorithm keeps a vector V of the furthest x reached
on each diagonal k, updates it in place for each edit distance d, and reads
the files by line number. **L0 has no arrays (limit 03)**, so:

- the points for one d are a list ordered by diagonal. The list for d + 1
  is built from it in one pass, since V[k] depends only on V[k−1] and
  V[k+1], which are neighbours in the list.
- instead of an index into each file, each point carries the rest of each
  file from where it is. Immutable lists share structure, so this is a
  pointer, and it takes the place of random access.
- instead of saving V at every step and walking back through the saved
  vectors, each point carries its own edit list, last edit first. The
  lists share their common prefixes.

This was not more code than the array version: `linediff.l0` is 205 lines,
comments included. The cost is time and memory when the files differ a lot.
Each step allocates a new list of points, a reversed copy of it, an edit,
and a cell for the edit list, per diagonal. The bare loop over V, without
the files, takes 1.40 s at D = 10,000 as lists, against 0.02 s for the same
loop in C over one array (`programs/limits/03-no-arrays.l0`). The edit
lists account for the rest of the 8.4 s and the 596 MB peak.

Apple's diff is fast at 100% changed for another reason too. It hashes lines
and drops lines that occur in only one file before it searches, which needs
a hash table. That could be written in L0 as a balanced tree, but it was
not needed for the 1% case, and was not attempted.

## Other costs

- **No generic list functions (limit 04):** `rev_fronts` and `rev_edits`,
  plus `length_strs` in the tests, are copies of `rev` and `length` for
  other element types.
- **The standard line reader cannot report a failed read.** `file_read_line`
  in `lib/io.l0` stops at any negative byte, so a read error looks like the
  end of the file, which the l0-code skill itself warns against. So
  `read_lines_from` is written here to tell them apart.
- A last line without a newline is treated like one with a newline. `diff`
  would print `\ No newline at end of file`, and linediff does not.
