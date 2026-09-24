# 0003: Link compiled programs against an IR runtime instead of C

Kind: language
Status: queued
Needs: 0001

## Why

Every compiled program links `runtime/l0core.c` and `runtime/l0rt.c`. The
goal is no C source in a compiled program. [0001](0001-shed-c-runtime-plan.md)
showed a replacement written as LLVM IR calling only libc,
[0001/proto-rt.ll](0001/proto-rt.ll), passing all 30 compiled tests and
self-compiling byte-identically on macOS arm64 and Linux aarch64.

## The change

- `spec/L0.md` section 10.3: the runtime is LLVM IR that calls libc, and
  exports the existing ten functions plus `void @l0_stack_check()`. Every
  compiled L0 function, program and prelude alike, calls it on entry.
- `spec/changelog.md`: the entry, quoting 0001's measurements, and why signals
  were given up for an explicit check.
- `compiler/emit.l0`: declare `@l0_stack_check` in the header and call it
  first in every function. Nothing in the compiler's source uses anything new,
  so this is one bootstrapped change, not two.
- `runtime/l0rt.ll`: the prototype, hardened. Known gaps: when `pthread_create`
  fails, the fallback guesses a 4 MB limit where it could ask `getrlimit`; and
  `read` returning an error is treated as end of file, as the C runtime does.
- `tools/l0ll`, `tools/l0`, `tools/test.sh` (backend and compiled suites), and
  `tools/install.sh` link `l0rt.ll` instead of the C objects. `install.sh`
  then compiles no C at all.
- `tools/build.sh` still compiles `l0core.c` for stage 0 only.
- Tests: a lang case for stack exhaustion, which nothing covers today, and the
  six backend tests relinked against `l0rt.ll`.

## Done when

- the checklist in the `l0-bootstrap` skill
- `nm` on a program built by `tools/l0 build` shows no symbol defined by
  `runtime/*.c`, and its undefined symbols are libc's alone
- a fresh clone installs with `tools/install.sh` without compiling C
- the seed is refreshed, so it carries the stack checks

## Log

- 2026-09-23: opened from 0001's answers.
