# 0006: Write ordinary programs and record where L0 stops

Kind: program
Status: done
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
- 2026-09-23: **the worker reported, and the claims were re-checked in the
  main tree.** Its `programs/` tree is copied into [0006/](0006/) as
  evidence; `0006/README.md` is its full write-up. Its scripts assume they
  sit at `programs/NAME/`, so run them from a checkout of its branch's layout,
  or run the binaries directly as the re-check below did.

  **The programs.** The line filter and the word counter run correctly over
  stdin, and both match their expected outputs here. Prompt and filecopy
  cannot be written at all.

  **The limits:**

  | # | Limit | Blocks | Evidence, re-checked here |
  |---|---|---|---|
  | 01 | stdin is read whole before `main` | filter, counter | 17 bytes per input byte before `main` does anything |
  | 02 | memory is never freed | filter, counter | 16 bytes per list cell ever created, however few are live |
  | 03 | output is held until `main` returns | filter, counter | 16 bytes per output byte |
  | 04 | no output before end of input | prompt, filter, counter | answer at t+0, first output at t+3.01 s, when input ends |
  | 05 | no command-line arguments | filecopy, filter | `l0 build`: `error: main must take one parameter of type (list int)` |
  | 06 | no files | filecopy | `unknown function 'read_file'`, `unknown function 'write_file'` |
  | 07 | no way to report failure but a crash | filecopy | `unknown function 'fail'` |

  **Memory, re-measured here** (peak footprint): the line filter 57 MB at 1
  MB of input and 563 MB at 10 MB, the counter 203 MB and 2.1 GB. The worker
  measured up to 300 MB of input, 16 GB for the filter, at a constant 53
  bytes per input byte; the counter's word table never holds more than 14
  entries and it still costs 208 bytes per input byte. Its decomposition: a
  collector alone would bring the counter to about 86 bytes per input byte,
  since the input and output lists stay live; streaming I/O alone would leave
  about 120 bytes per input byte of garbage. Bounded memory needs both.

  **Four spec findings**, each confirmed:
  1. Checking does not enforce `main`'s signature. With `#nomain`, which
     `l0check` and `l0 check` always pass, a `main` with the wrong signature
     checks `ok`, and only `l0 build` rejects it, with no file or line.
     Section 9.1 says `#nomain` "relaxes nothing else", but in practice it
     relaxes this too. The worker nearly recorded limit 05 as passing because
     of it.
  2. Section 8's "a runtime error produces no standard output" holds only
     because output is written after `main` returns. Streaming output has to
     revise it.
  3. Section 10.3's case for the arena is wrong as stated: a single bounded
     run already reaches 9.8 GB resident for 1 KB of live data. What must fit
     is total allocation, not the length of the run.
  4. Long loops survive only because LLVM turns tail calls into jumps: the
     counter exhausts the stack on 10 MB at `-O0` and completes at `-O1`.
     Section 8 leaves tail calls unspecified and never defines tail position.

  **The worker's view**, kept apart from the facts: six facilities, none of
  them new syntax (reclamation, incremental stdin and stdout, arguments, files
  behind an opaque handle, stderr and an exit status), and high-level ones
  rather than raw primitives, because an error result as a data type is
  something exhaustive `match` already enforces, while raw memory gives the
  checker nothing. Its own mistakes were all ones no checker catches today:
  dropping a last line with no newline, an input generator that would have
  grown the table without bound, and trusting `l0check` on limit 05.
