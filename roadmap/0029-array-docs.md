# 0029: Say what arrays really cost

Kind: language
Status: done, changelog "What updates an array in place, said correctly, and
no language change for it"
Needs: 0028

## Why

From [0028](0028-programs-with-arrays.md): all three workers found section
6.5 and the shipped skill wrong or silent about how arrays behave, and two
were misled by it.

- An array in a data value updates in place when the value is taken apart
  at its last use: `0028/grids/probes/probe.l0` and `0028/text/exp/wrap.l0`
  show 0 copies, and union-find's `UF` and wordfreq's table rely on it. The
  spec and skill say it copies.
- A read of an array nested in a later operand, after an `array_set` of it
  in an earlier one, copies every time: `0028/algorithms/limits/03`. The
  skill says reading in the same expression is fine.
- `(array_new h (array_new w x))` shares one row, which copies on first
  update; nothing says so. Nor that `array_new` costs its length.
- Reading input of unknown length into an array costs what a list does
  (`0028/text/limits/01`).
- Nested `(push a (push b acc))` pushes `b` first, which cost a test.
- The repo's `l0-code` skill says to run programs with `build/l0i run`,
  which cannot parse arrays; the checker's unknown-type message does not
  list arrays; section 10.3 has a missing period; `L0_ARRAY_STATS`'s third
  line is undocumented.

## Done when

The spec says what is true, the skills say how to write for it, and the
checker's message names arrays, with the l0-bootstrap checklist for the
message change.

## Log

- 2026-09-28: opened from 0028.
- 2026-09-28: done. Section 6.5 lists each case; the shipped skill shows the
  `let` that avoids the read-after-update copy, says to use flat arrays for
  grids and that data values are fine, what input held as an array costs,
  and push order; the repo skills point at `tools/l0 run`; the parser's type
  messages name `(array T)`, with a new case in `tests/compiler/parse_errors`.
  Both suites green; seed refreshed. No runtime or emitter change, so no
  Linux run. Next is 0030.
