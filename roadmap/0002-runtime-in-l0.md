# 0002: Write the runtime in L0

Kind: program
Status: active
Needs: nothing

## Why

Question 1 of [0001](0001-shed-c-runtime-plan.md) asks whether the runtime
should be written in L0. The fastest way to find out what that would take is to
try, and record exactly where L0 as it stands cannot express it. Those limits
are the Why for whatever language items follow.

## The task

In a worktree, write `programs/runtime/runtime.l0`: the jobs in 0001's table,
written in L0 as far as L0 allows. That means allocating a cons cell and a
data block, `head`, `tail`, and `div` with their runtime errors, reading all
of stdin into a byte list, writing a result as bytes, as a decimal `int`, or as
`true`/`false`, and the entry point.

When L0 cannot express something, stop that part. Write the smallest program
that shows the limit, confirm with `tools/l0check` that the failure is real,
and move on to the next job. Do not write a workaround. For each limit, also
write the code you would have written if L0 allowed it, since that is the
first draft of the language item.

Do not edit `spec/`, `compiler/`, `runtime/`, `bootstrap/`, `stage0/`,
`lib/prelude.l0`, or `roadmap/`. Run `tools/build.sh` before `tools/l0check`,
because `build/` starts empty in a worktree.

## Done when

- every job in 0001's table has either L0 that `tools/l0check` accepts or a
  recorded limit
- each limit has the smallest failing program, the checker's output, and the
  code that should have been possible
- the coordinator has re-checked each limit in the main tree and logged it here

## Log

- 2026-09-23: opened. Suits a `best-of-n-runner` subagent, following the
  `l0-roadmap` skill's instructions for program workers.
- 2026-09-23: launched as a `best-of-n-runner` worker. Its worktree starts from
  the last commit, which predates `roadmap/`, so the task was given in full in
  the prompt. It writes only under `programs/runtime/`.
