# 0027: A faster compiler

Kind: tooling
Status: done, changelog "Programs and the runtime are optimized together, and
no language change for it"
Needs: 0024

## Why

Chosen by the user after 0024: use arrays in the compiler or prelude where
they would speed it up. The compiler takes 0.15 s on its own source, and runs
for every test the compiled suite builds.

Profile, 2026-09-28: the seed-built compiler compiled with LLVM's IR
instrumentation (`-fprofile-generate`) and run on its own source, basic
blocks executed per function (20.9 million in all):

| function | blocks | share | what it is |
|---|---|---|---|
| `rev_onto` | 6.87 M | 33% | the prelude's reverse, mostly under `append` building output |
| `list_eq` | 5.15 M | 25% | comparing names, from the lookups below |
| `split_spaces_onto` | 3.43 M | 16% | word tables re-split on every call |
| `find_sig` | 0.76 M | 4% | signatures, a linear list searched by name |
| `pad_of`, `nth_int` | 0.89 M | 4% | tail-call padding by name, and arities indexed as a list |

The word tables are `is_builtin` and its kin: about 8,000 calls, one per call
site in the checker and again in the emitter, each re-splitting seven tables
from string literals, since L0 has no top-level constants.

Where arrays would help: a hash table for signatures, constructors, data
types, and pads (about 10-15%), the builtin names once built once (most of
the 16% and its share of `list_eq`), and the padding pass's arities, which
`spread_edge` reads and writes by index through a list. Where they would
not: `rev_onto` under `append`, which is how the emitter builds strings.

## The blocker

`tools/l0check` runs the compiler's own checker under the stage-0
interpreter, and `tests/compiler` runs the compiler's stage tests under it as
the oracle half of the differential check. Stage 0 is frozen and has no
arrays, as it has no I/O builtins, which is why the skills already forbid
those in `compiler/*.l0` and `lib/prelude.l0`. So the compiler cannot use
arrays without first moving `tools/l0check` and the interpreted half of
`tests/compiler` onto the compiled compiler, which gives up stage 0 as an
independent run of the compiler's own code.

## Log

- 2026-09-28: opened; profiled; blocked on the stage-0 question, put to the
  user.
- 2026-09-28: the user chose to keep stage 0 and speed the compiler up
  without arrays. Building the builtin table once cut 23% of the L0's blocks
  and no time: the profile above counted only the compiled L0, and with the
  runtime instrumented too the L0 was 16 of 334 million blocks, the rest
  counting, allocation, and 55 million uninlinable calls to `head`, `tail`,
  and `is_empty`. `-flto` on every link, with the runtime as bitcode, halved
  the time, and under it the table change is worth a quarter: the compiler
  on itself 181 ms to 93 ms, same output; Myers' sweep 0.17 s to 0.08 s.
  Builds are slower (small program 161 to 215 ms, the compiler 0.5 to 2.1
  s); the user chose it everywhere over the compiler alone. Done; arrays in
  the compiler stay blocked on stage 0, and `rev_onto` under `append` is the
  next cost if the compiler needs to be faster again.
