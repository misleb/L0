# 0031: A new builtin does not take over a program's function

Kind: language
Status: queued, next
Needs: 0026

## Why

From [0026](0026-packed-bytes.md)'s prototype: spec 7 says that in call
position "the builtin always wins", so adding a builtin silently takes over
every function of that name that programs already define, and the program
then fails with a type error in its own code. The prototype's first names
broke three existing programs (`write_bytes` broke 0028's sort and
`exp/sort_chunks.l0`, `bytes_of` broke `tests/unit/kvlog_test.l0`, and
`read_all` would have broken `lib/test.l0`'s users, json's tests, and
editdist), so it had to pick names nobody uses rather than names that say
what the builtin does.

The smallest program, `0031/01-builtin-takes-over.l0`, has its own `flush`,
as a program written before 0018 made `flush` a builtin could:

```
(def flush ((s (list int))) int (head s))

(def main () int (flush "abc"))
```

```
roadmap/0031/01-builtin-takes-over.l0:4:18: error: an argument of flush must be int, but this is (list int)
```

Spec 7.1 already has the answer for the prelude, for the same reason: a
program's function wins over the prelude's of the same name, because
"without it, adding a function to a prelude breaks every program that had
already defined that name". Builtins have no such rule, and 0032 is about to
add six.

## Done when

The rule settled in the spec first. Weigh at least:

- a program's `def` wins over a builtin of the same name, as it does over the
  prelude, so adding a builtin breaks nothing; and whether a prelude `def`
  wins over a builtin for the prelude's own calls
- the builtin still wins but a `def` of a builtin's name is an error that
  says so, so adding a builtin breaks loudly and at the definition

Then the l0-bootstrap checklist, and:

- stage 0 is frozen with the old rule, so a test of the new rule, a program
  calling its own function named like a builtin, belongs in `tests/io` or
  `tests/unit`, never `tests/lang`
- `compiler/`, `lib/prelude.l0`, and the rest of `lib/` checked for a `def`
  named like a builtin, whose calls the new rule would change
- the program above checks, and runs, exiting with 97; then `0031/` is
  deleted

## Log

- 2026-09-29: opened from 0026's finding; queued ahead of 0032 so that
  0032's builtins can be named for what they do.
