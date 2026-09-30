# 0037: A program's types do not collide with the library's

Kind: language
Status: queued
Needs: 0036

## Why

[0035](0035-type-parameters.md): once 0036 lands, `lib/io.l0` should define
`Option`, `Result`, and a pair once for every program. But type and
constructor names are global across the prelude and the program (spec 7.1),
and twelve `.l0` files here already use `Ok`, `Some`, `Pair`, or the like
(0014's calc, 0028's json, kvstore's tests, `tests/lang/last_use.l0`,
`lib/examples.l0`). Adding them to the library would break every one, which
is what 0031 stopped for functions. Only names beginning `Io` are reserved
for the library today, which would make the shared types `IoOption` and
`IoResult`.

## The question for the spec

Whether a program's type or constructor shadows a library one of the same
name, as a program's function does, with the checker telling same-named
types apart by group despite 7.1's two reasons for keeping them global; or
whether the library's general types get names reserved some other way.

## Done when

- the l0-bootstrap checklist
- a program that defines its own `Ok` still compiles and runs with a
  library that defines one

## Log

- 2026-09-30: queued from 0035, after 0036.
