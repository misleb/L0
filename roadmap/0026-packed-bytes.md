# 0026: Bytes held one byte per byte

Kind: language
Status: proposed
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

## Done when

A program that needs it, then the l0-bootstrap checklist.

## Log

- 2026-09-25: opened from 0021's finding.
