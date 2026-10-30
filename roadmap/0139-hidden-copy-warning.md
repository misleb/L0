# 0139: the checker warns of an update that a later use makes copy

Kind: tooling
Status: proposed
Needs: nothing

## Why

The hidden whole copy, an `array_set`, `map_put`, or now a field
replacement whose value is still used afterwards and so copies, recurred at
least four times, each found only as a slowdown on real data: 0028's heap,
0056's `map_remove`, "the third time, by an author who knew the rule", and
twice in one L0S session (0131). 0131 documented it and left the warning
open, since it would be L0's first. The emitter already computes liveness
at every node; the warning is a check of whether the consumed operand of
`array_set`, the row form, `(.f e v)`, and a call whose argument is read
after it, is live after the expression. The smallest program it would have
caught: `(Seen (map_put m k true) (if (map_has m k) n (add n 1)))`.

## Decide first

- what a warning is: a line on standard error after a successful check,
  `file:line:col: warning: ...`, the compile still succeeding, and `l0
  check` still saying `ok`; whether `l0 build` prints it
- the wording, which names the variable and where its later use is: `m
  is used again at 7:30, so this map_put copies it; read first, with let`
- the false positives: a read after the update inside the update's own
  call is in place (6.5), and must not warn
- whether the spec says warnings exist, in section 8 or 9.1's protocol,
  or whether they are the tool's alone

## Done when

- the compiler's output protocol carries the warning, `tools/l0` and
  `tools/l0check` show it, and `tools/test.sh` can pin one
- `tests/compiler/warn_copy` holds the cases, both shapes of the trap and
  the in-place reads that must stay quiet
- the skills say the checker now says it

## Log

- 2026-10-30: opened, from the review (its item 1.5) and 0131; proposed.
