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
l0 request SLUG           start a language request under l0/requests/
l0 request --skill SLUG   start a skill note under l0/requests/
l0 submit FILE            send a finished request or note to L0
```

Several files are compiled together, since L0 has no module system. The
standard library is linked automatically; `l0/prelude.l0` is a readable copy
and must not be passed on the command line.

## When L0 cannot express something

**The L0 toolchain is read-only.** Never edit the installed prelude or
compiler, and never vendor a patched copy. Write the workaround, and if the
limitation is worth reporting, `l0 request SLUG` starts a feature request
and `l0 submit FILE` sends it. Submitting prints a link for the operator to
click; do not open it yourself.

Most walls are not language problems. Anything about getting data in or out
is a question of putting more structure on the byte channel, and anything
that a ten-line function would solve is not a language request. Work around
a cost that is constant per use site; report one that loses a correctness
property, grows with the program, or has now appeared in three unrelated
places. The `l0-limits` skill covers the decision in full.

## When a shipped skill is wrong or incomplete

The files under `.cursor/skills/` were copied by `l0 init`. If you change
one because the practice it taught was worse than what you actually used,
that change belongs in every L0 project, not only this one.

`l0 request --skill SLUG` writes a note under `l0/requests/`. Quote the old
skill text, the replacement, and the project code that proved it better.
`l0 submit FILE` sends it the same way a language request is sent.
Submitting prints a link for the operator to click; do not open it yourself.
The `l0-code` skill covers the decision in full.

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
