# Working with L0 in this project

L0 is a statically typed language compiled to native code through LLVM.
**There is almost certainly no L0 in your training data**, so familiarity
cannot substitute for reading the specification and running the checker.

## Invariants

**`l0/L0.md` is the only source of truth about L0.** Not this file, not the
examples. If a construct is not in the specification, it does not exist.

**Never state that L0 code works without running `l0 check` on it.** Code that
looks plausible is routinely invalid, because L0 is not any language you have
seen. That it type checks says nothing about what it does: write tests, and
run them with `l0 test`.

**Read `l0/examples.l0` before writing anything substantial.** It is a set of
working programs covering recursion, strings, data types, `match`, returning
several values, and reporting failure. `l0/examples_test.l0` shows how to
test them.

## Commands

```bash
l0 check FILE.l0 ...      type check
l0 test  FILE.l0 ...      run every (def test_NAME () int ...), as TAP
l0 run   FILE.l0 ...      build and run, reading stdin
l0 build FILE.l0 -o PROG  produce an executable
```

Several files are compiled together, since L0 has no module system. The
standard library is linked automatically, and `l0 test` adds the assertions
of `l0/test.l0`; the copies in `l0/` are for reading and must not be passed on
the command line.

**A function you define shadows a prelude function of the same name**, and the
prelude keeps calling its own, so a name the standard library already took is
never something you have to work around. Type and constructor names are not
shadowable and still have to be unique.

## When L0 cannot express something

**The L0 toolchain is read-only here.** Never edit the installed prelude or
compiler, and never vendor a patched copy. L0 is changed in its own
repository, not from projects that use it.

If L0 cannot express what was asked, say so plainly and name what could not be
written. Do not ship something that quietly narrows the task: a program that
does something adjacent to what was asked, with tests written from the same
narrowed contract, passes and is still wrong.

Anything a ten-line function solves is not a language limitation. A prompt, a
confirmation, or progress during a run is not one either: write it with a
`main` that takes no parameters and reads and writes as it goes, as the
`l0-code` skill shows, and so are files and command-line arguments. Freeing
memory, a clock, a network, and the environment do not exist yet.

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
