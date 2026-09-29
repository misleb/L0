# 0026: How L0 holds bytes one byte per byte

Kind: research
Status: proposed, next among research; earned by 0028
Needs: 0024

## Why

From [0014](0014-programs-round-two.md)'s limits
`0014/data-structures/limits/04-bytes-are-cons-cells.l0` and
`0014/bytes-encodings/limits/02-bytes-as-lists.l0`: holding bytes as a list
costs 24 bytes per byte, so json held an 11.5 MB document in 276 MB, and
building lines was half of minigrep's time. [0021](0021-arrays-route.md)
measured holding 10 MB: 242 MB as a list and 82 MB as an `(array int)`. A
packed type would hold it in about 11 MB.

Not ready: arrays, 0024, cut the worst case by three and may change what
those programs would be written as. This needs a program written with
arrays that still fails on memory or speed. Building an array from a list
peaks at both at once, since freed cells stay on the free lists, so reading
input straight into packed bytes or an array belongs here too.

**Earned by [0028](0028-programs-with-arrays.md).** Its json and sort hold
their input as an array and still peak at 25 bytes a byte, because a program
cannot learn its input's length before reading it, so the array doubles and
the last doubling holds both copies (`0028/text/limits/01-input-into-array.l0`,
re-checked: 10 MB of input peaks at 257 MB growing, 82 MB at exactly the
right size, 85 MB in 64 K chunks, 242 MB as a list; Python 18 MB). Words as
hash keys cost 24 bytes a byte too, 37 of wordfreq's 54 MB. The worker's
hypothetical is `(read_all 0)` returning packed bytes.

## Done when

A written finding, with measurements, that settles: whether a packed type is
needed or an input builtin reading into an array of the right size is enough
first (it alone would take 257 MB to 82); if a packed type, its builtins, how
string literals and the list-based library meet it, and its layout; what it
costs the properties the l0-bootstrap skill lists; and the language items it
breaks into, each one bootstrapped change.

## Log

- 2026-09-25: opened from 0021's finding.
- 2026-09-28: earned by 0028's text programs; made a research item, by the
  user's choice, since the question of what to build comes first.
