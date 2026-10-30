# 0139: the checker warns of an update that a later use makes copy

Kind: tooling
Status: done
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
- `roadmap/l0s-adoption.md` shows the warning's wording, so L0S's agent
  can run `l0 check` over its tree and read the list it gets

## Log

- 2026-10-30: opened, from the review (its item 1.5) and 0131; proposed.
- 2026-10-30: done. Decided: a warning is a line `FILE:LINE:COL:
  warning: ...` after a successful check, never failing it; the compiler
  writes it before the IR as an LLVM comment, so the protocol keeps two
  tags, and `tools/l0check` and `tools/l0` print it; spec 9.1 says a
  compiler may warn. The wording names the variable and the update, not
  the later use's position, which `live` does not carry. What counts as an
  update is `array_set` and a call whose parameter, or a field of it, the
  callee updates (`module_updates`, a fixpoint beside the read-only
  flags); a field replacement alone is not, since it gave 11 warnings on
  the compiler, every one a record extended on purpose. In-place reads
  inside the update's own operands stay quiet. `tests/compiler/warn_copy`
  holds 12 cases. The compiler's own source has none; `lib/examples.l0`'s
  `tally` had one, a real copy per call, fixed. Both suites, the
  fixpoint, and `--virt` on both boards green.
