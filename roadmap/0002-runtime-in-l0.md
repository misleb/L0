# 0002: Write the runtime in L0

Kind: program
Status: done
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
- 2026-09-23: **the worker reported, and every claim was re-checked in the
  main tree.** Its files are copied into [0002/](0002/) rather than merged,
  since none of it belongs in the language: `runtime.l0` is the part of the
  runtime L0 can express, `runtime_test.l0` its 51 assertions (all pass here,
  through `tools/l0 run`), `limits/` the smallest program per limit, and
  `hypothetical/` the code each limit prevented, which does not check.

  **What L0 can express:** only the pure computation. The layouts of cons
  cells and data blocks as offsets, the error checks and their messages
  (byte-identical to the runtime's), the arena's rounding and bump
  arithmetic, decimal and boolean rendering, and parsing `L0_STACK_MB`.

  **The ten limits**, each reproduced here with the current checker:

  | # | Limit | Blocks | Checker says |
  |---|---|---|---|
  | 01 | no load or store at an address | lists, blocks, all buffers | `unknown function 'load_word'` |
  | 02 | no state that outlives a call | the arena's bump pointer | `expected a top-level (def ...) or (data ...)` |
  | 03 | no call to a function not written in L0 | every OS job | `unknown function 'malloc'` |
  | 04 | a typed result cannot be handled as the word it is | one entry point for every `main` type | `l0_entry declares return type int, but its body is (list int)` |
  | 05 | no function values | `pthread_create`, signal handlers | `'run' is a function, and L0 has no function values` |
  | 06 | no way to choose a symbol name | the process `main`, and `@l0_cons` itself | `function 'main' is already defined` |
  | 07 | no C types: no 32-bit int, pointer, or void | C signatures | `unknown type 'i32'` |
  | 08 | `div` lowers to `@l0_div`, the function being written | the division itself | checks; the IR shows the self-reference |
  | 09 | prelude-group code cannot call the program's `main` | a runtime shipped as a library | `unknown function main` |
  | 10 | anything returning two values or a string allocates | code beneath the allocator | checks; the IR shows `@l0_data_new` |

  Limit 10 constrains rather than blocks: `runtime.l0` keeps allocator-level
  code to functions returning `int` or `bool`. Limits 04 to 07 and 09 are all
  about the entry point and the thread, which 0003 has since placed in
  `runtime/l0rt.ll`, where nothing needs L0 to express them.

  **The worker's view of the smallest set of additions**, kept separate from
  the facts above: memory access, static storage, and calls to C functions,
  with the compiler emitting the per-program entry point and inline checks;
  the big stack is platform-specific and best decided separately.
