# 0021: How L0 gets arrays, compact bytes, and in-place update

Kind: research
Status: proposed
Needs: 0020

## Why

The next goal, by the user's choice from [0014](0014-programs-round-two.md)'s
evidence. All three workers hit the lack of an indexed table, and it cost
more than anything else they hit:

- `0014/text-tools/limits/01-no-array.l0`: a byte histogram of 1 MB takes
  1.48 s as a list of counts and 0.33 s as a depth-8 tree, re-checked in the
  main tree; reading the bytes alone is a small fraction of either. wordfreq
  is 9 times slower than Python, a third of it rebuilding tree paths to add 1.
- `0014/data-structures/limits/01-no-indexed-table.l0`: Dijkstra over a
  persistent trie is 3 times slower than CPython, with 61% of a query in
  reference counting on nodes only being read. Checker output:
  `expected list after ( in a type`, and `unknown function array_new`.
- `0014/bytes-encodings/limits/03-no-arrays.l0`: Myers' diff at D = 10,000
  takes 1.40 s rebuilding its vector, against 0.02 s over a C array.

Two workers also hit bytes held as cons cells, 24 bytes each: holding 10 MB
of input peaks at 242 MB, re-checked, and building lines is half of
minigrep's time (`0014/data-structures/limits/04`, `0014/bytes-encodings/limits/02`).

The workers' hypotheticals all want an array whose update happens in place
when nothing else holds it. Under today's release rule a loop's own
reference is still held when the update runs, so that needs a value released
at its last use: [0013](0013-release-at-last-use.md)'s rule, dropped then for
lack of a use, and this would be one.

## Done when

A written finding that settles, with measurements: the type and builtins, how
an array is laid out and counted, whether bytes are a separate packed type
or an array of `int`, the release rule in-place update needs, what each
costs the properties the l0-bootstrap skill lists, and the language items it
breaks into, each one bootstrapped change.

## Log

- 2026-09-24: opened from 0014, after the I/O gaps 0018 to 0020.
