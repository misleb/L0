# Working with L0 in this project

L0 is a small, pure, statically typed language. **There is almost certainly no
L0 in your training data**, so familiarity cannot substitute for reading the
specification and running the checker.

## Invariants

**`l0/L0.md` is the only source of truth about L0.** Not this file, not the
examples. If a construct is not in the specification, it does not exist.

**Never state that L0 code works without running `l0 check` on it.** Code that
looks plausible is routinely invalid, because L0 is not any language you have
seen.

**Read `l0/examples.l0` before writing anything substantial.** It is a set of
working programs covering recursion, strings, data types, `match`, returning
several values, and reporting failure.

## Commands

```bash
l0 check FILE.l0 ...      type check
l0 run   FILE.l0 ...      build and run, reading stdin
l0 build FILE.l0 -o PROG  produce an executable
```

Several files are compiled together, since L0 has no module system. The
standard library is linked automatically; `l0/prelude.l0` is a readable copy
and must not be passed on the command line.

## Two traps specific to L0

**Quadratic output.** Building output by appending is quadratic; it passes
every small test and then appears to hang on real input. Accumulate with
`push` onto a reversed list and call `rev` exactly once at the end.

**Deep nesting and parentheses.** Long `if` and `or` chains end in a dozen
closing parens and are the most common source of parse errors. Use
`split_spaces` with `any_eq` for membership tests, and split any function
nesting more than about four levels deep.

The `l0-code` skill covers both in detail, along with the syntax that differs
from what other languages would lead you to expect.
