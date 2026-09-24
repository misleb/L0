# 0006: Write ordinary programs and record where L0 stops

Kind: program
Status: active
Needs: nothing

## Why

[0002](0002-runtime-in-l0.md) tried to write the runtime, so every limit it
found is a systems limit. [0005](0005-memory-and-io-route.md) has to weigh
that against what ordinary programs need, and has no evidence for that yet.

## The task

Write a handful of small, ordinary programs, each in its own directory under
`programs/`, chosen so that between them they need what a general-purpose
language is expected to provide:

- a line filter that must run in memory proportional to one line, on an input
  far larger than memory would allow if nothing were freed
- a program that asks a question and answers the reply, as in "Output before
  input is an accepted blocker" in the changelog
- a program that reads a file named on its command line and writes another
- a long-running loop that keeps a small amount of state, such as a counter
  or a table updated per input line

Apply the same rules as 0002: when L0 cannot express something, stop that
part, write the smallest program that shows it, confirm with `tools/l0check`,
and write the code that should have been possible. For memory, measure it:
record peak memory against input size, so a limit is a number and not a
claim. No workarounds, unless one is asked for and named as one.

Do not edit `spec/`, `compiler/`, `runtime/`, `bootstrap/`, `stage0/`,
`lib/prelude.l0`, or `roadmap/`. Run `tools/build.sh` first in a worktree.

## Done when

- each program is either written and checked, or has its limits recorded
- each limit has the smallest failing program, the checker's output or the
  measurement, and the code that should have been possible
- the coordinator has re-checked each limit in the main tree and logged it
  here

## Log

- 2026-09-23: opened as the evidence for 0005's question 4. Suits a
  `best-of-n-runner` worker, as 0002 did.
- 2026-09-23: launched as a `best-of-n-runner` worker, with the task given in
  full in its prompt since its worktree predates this file. It was also asked,
  separately from its facts, which route would let the checker catch more of
  the mistakes it made.
