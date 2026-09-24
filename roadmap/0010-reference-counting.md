# 0010: Reclaim memory by reference counting

Kind: language
Status: queued
Needs: 0009

## Why

From [0006](0006-ordinary-programs.md), `0006/limits/02-no-reclamation.l0`: a
loop that never holds more than 64 list cells at once, about 1 KB, reaches
9.8 GB after 10 million iterations, at 16 bytes per cell ever created. With
streaming I/O in place, 0006 estimates the word counter would still produce
about 120 bytes of garbage per input byte, never freed.

Reference counting is complete for L0, with no cycle collector, because an L0
heap cannot contain a cycle: there is no mutation, evaluation is strict, and
`let` cannot define a recursive value (section 5.3). See
[0005](0005-memory-and-io-route.md).

## Open questions for this item

- How the emitter keeps the types it now discards, and how a heap block says
  which of its words are pointers, since a cons cell's head may be an `int`.
- Where increments and decrements go, and whether updating in place when a
  count is one comes in the same change or later.
- How to split it into bootstrapped changes. It is invisible to programs, so
  the whole differential suite keeps judging it against stage 0.
- Section 10.3's case for the arena is corrected here: what must fit in
  memory is total allocation, not the length of the run.

## Done when

- the checklist in the `l0-bootstrap` skill
- `0006/limits/02-no-reclamation.l0` runs in memory that does not grow with
  its iteration count
- the compiler compiling itself peaks below its current 74.5 MB

## Log

- 2026-09-23: opened from 0005's recommendation.
