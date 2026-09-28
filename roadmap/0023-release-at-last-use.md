# 0023: Release a value at its last use

Kind: language
Status: queued
Needs: 0021

## Why

From [0021](0021-arrays-route.md)'s prototype, branch
`proto/arrays-release-at-last-use`. Under today's rule a binding keeps its
reference until its scope ends, so in every loop that threads an array
through tail calls the array's count is 2 when it is updated, and an update
that could be in place copies the whole array: Myers' diff at D = 10,000
took 77 s with arrays against 1.37 s with lists, 50,005,000 copies. With
this rule it takes 0.156 s and copies nothing, and the byte histogram and
Dijkstra likewise (0021's table). Arrays, 0024, are not worth having
without it.

It is earned before any array exists, too: the compiler compiling itself
goes from 0.26 s and 27.3 MB to 0.15 s and 20.6 MB, and its IR is 15%
smaller, with two thirds fewer increments and releases. 0013 built a
weaker version (one use, outside any branch) and measured nothing; the
difference is releasing at the last use on every path, through branches and
match arms, with borrowing that takes no reference at all.

## Done when

The l0-bootstrap checklist, plus:

- section 10.3 states the rule, replacing its ownership bullets and "freed no
  later than the end of the scope", and section 8 states that a call takes
  its variable operands after its other operands, as a guarantee rather
  than a freedom, since whether a loop updates in place will depend on it
- `tests/lang/last_use` or its equivalent covers shadowing, a variable used
  in one branch only, a borrowed match subject, a repeated operand, and an
  unused binding or parameter, and fails under `L0_RC_CHECK` when the
  branch-start release is removed, as the prototype's did
- the compiler on itself measured before and after, and nothing reported
  live under `L0_RC_CHECK` when it compiles itself

The prototype's `emit.l0` changes (+348 / -159) are a starting point, to be
redone spec-first in the main tree.

## Log

- 2026-09-25: opened from 0021's finding.
