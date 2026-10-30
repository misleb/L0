# 0137: a one-field wrapper costs nothing

Kind: language
Status: proposed
Needs: nothing

## Why

Spec 6.12 says a region "is an int naming it" and that regions, handles,
spaces, frames, CPUs, and interrupts are "numbered apart" and "neither is
ever the other"; the checker cannot see any of it, since wrapping an `int`
in a data type, `(data Space (Space int))`, allocates a block with a header
and a tag. So the builtins take bare ints and a kernel keeps them, and
passing a frame where a space is due is `not a space` at run time rather
than a compile error. The library wraps a few, `IoFile` and `IoDevice`, at
that cost. The smallest program that cannot be written without paying for
it: a kernel whose spaces and frames are different types.

## The rule

A data type with exactly one constructor of exactly one field of type
`int`, `bool`, or `float` is represented as that word (10.1): its block's
mask bit is clear, construction and `match` are the identity, and `eq` and
`compare` are the field's. Its `hash` changes: the tag item disappears
(6.9), so a program that pinned or stored the hash of such a type notices;
L0S's tests mention `hash` twice, to be checked first. Nothing crosses the
process ABI, which passes words and bytes.

## Done when

- the checklist in the l0-bootstrap skill
- spec 10.1, 6.9, and 6.8 state the representation and what follows
- `tests/unit` covers construction, `match`, `eq`, `hash`, `compare`, and
  a wrapper as a map key; `tests/io/libdoc/index.txt` if the library wraps
  a new builtin
- after the seed is refreshed: the library offers typed spaces and frames,
  or says why not, and the kernel uses them
- `roadmap/l0s-adoption.md` says which of L0S's `hash` uses change, if
  any, and how to wrap its handles

## Log

- 2026-10-30: opened, from the review (its item 1.3); proposed.
