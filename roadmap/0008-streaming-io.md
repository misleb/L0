# 0008: Streaming standard input and output

Kind: language
Status: done
Needs: 0007

## Why

From [0006](0006-ordinary-programs.md). The prompt program cannot be written.
The nearest L0 program, `0006/limits/04-no-output-before-eof.l0`, prints its
question after its answer was consumed. Re-measured here, with the answer
supplied at t+0 and end of input at t+3:

```
  t+ 0.00s  stdin  b'Ada\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'What is your name? Hello, Ada!\n'
```

What should have been possible, `0006/hypothetical/04-no-output-before-eof.l0`:

```
(def main ((args (list (list int)))) int
  (let asked (write_stdout "What is your name? ")
    (let name (take_line (read_line))
      (let greeted (write_stdout (append "Hello, " (append name "!\n")))
        0))))
```

It also removes 0006's limits 01 and 03: the whole input held before `main`
runs, at 17 bytes per input byte, and the whole output held until it
returns, at 16 bytes per output byte.

## Open questions for this item

- The builtins' names, types, and failure behavior; whether output is
  flushed before every read, as the hypothetical assumes.
- Whether the existing `main` of section 9 remains, alongside a new form,
  since every current program and the compiler use it.
- Section 8's "a runtime error produces no standard output" must be revised,
  since streamed output is already written when an error happens.
- Stage 0 cannot run the new builtins, so their tests have no oracle. Say how
  they are tested instead.

## Done when

- the checklist in the `l0-bootstrap` skill
- the prompt program is written in L0, checks, and asks before it reads, by
  `0006/prompt/measure.sh`'s timing

## Log

- 2026-09-23: opened from 0005's recommendation.
- 2026-09-23: done; changelog "Reading and writing as a program runs". The
  open questions were answered as follows:
  - builtins `read_byte` (-1 at end of input) and `write_byte`, with
    `read_line`, `write_str`, and `write_line` in L0 in a new `lib/io.l0`,
    which `tools/l0` links in the prelude group; output is flushed before any
    read that would wait, and at exit, including from a runtime error
  - the existing `main` stays; a second form, `(def main () int ...)`, reads
    nothing up front and returns the exit status
  - section 8 now lets bytes written before a runtime error through, and
    says an evaluation may be moved or dropped only if it can neither do I/O
    nor fail
  - the new `tests/io/` suite runs under `--compiled` only, with hand-written
    expectations, and `prompt.sh` tests the timing through named pipes
  Measured: the prompt built with `l0 build`, answer sent at t+2, shows its
  question at t+0.01 and its greeting at t+2.00, and exits without waiting
  for end of input; `prompt.sh` fails a read-first version. A streaming copy
  of 100 MB peaks at 1.1 MB, against 1704 MB for `main` returning its input.
  Both suites pass (56 interpreted, 59 compiled), the fixpoint holds, the
  seed is refreshed, and a fresh copy installs and bootstraps.
