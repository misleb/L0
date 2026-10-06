# 0047: the compiler uses type parameters and eq

Kind: language
Status: queued
Needs: 0046

## Why

[0044](0044-compiler-free-of-stage0.md) and
[0035](0035-type-parameters.md): with the prelude generic, the compiler
still carries 19 per-type `rev`, `length`, and `append` copies
(`rev_diags_onto`, `rev_tys_onto`, `length_exprs`, `append_sigs`, ...), 73
calls to `list_eq` and the hand-written `ty_eq`, `tys_eq`, and `bools_eq`
that `eq` replaces, and nine parser and checker result types of one
`Result` or `Option` shape.

## Done when

- the per-type copies are gone, and their callers use the prelude's
- `eq` replaces `list_eq`, `ty_eq`, `tys_eq`, and `bools_eq` in the compiler,
  where it is the same comparison
- the result types are `Option` or `Result`, unless one carries something
  those cannot, which the Log names
- both suites green, the fixpoint holds, the seed refreshed, and the
  changelog says what the compiler gave up writing by hand. Split by file
  if one change is too large to review

## Log

- 2026-10-05: queued by 0044.
