# 0038: Functions take type parameters

Kind: language
Status: proposed
Needs: 0036

## Why

[0035](0035-type-parameters.md): most of the lines that exist for want of
generics are helpers, not declarations: about 100 in the compiler (`rev_*`,
`length_*`, `append_*`, `find_*`), the prelude's `(list int)`-only `rev`,
`length`, and `append` with a copy for strings beside them, array grow
helpers rewritten in five 0028 programs, and 0014's trie written three
times. Parametric data alone removes none of these.

## Design, from 0035

- a parameter's type is matched one way against its argument's, so no
  inference; a result type mentioning a parameter no parameter mentions
  must be written at the call
- compiled once per combination of whether each type parameter's values
  are counted, which is the only thing `ty_is_ptr` asks, so no runtime
  change and no hidden argument
- no function values, so a generic container that compares keys still
  needs a comparison per key type; keys of `int`, `(list int)`, or `bytes`
  with values of any type cover every map in 0014 and 0028

## Done when

To be written when 0036 has landed and a program in the repository shows
which helpers it needs first.

## Log

- 2026-09-30: proposed by 0035.
