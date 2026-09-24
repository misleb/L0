# Working in this repository

L0 is a programming language being built in this repository, by you, for your
own use. Compiling itself is the goal that shaped it, and it must keep doing
so: that is the one property no change may cost. That goal has been reached
and no longer sets the direction. L0 is now being made general purpose:
compiled to native code through LLVM, with no C in a compiled program, and
gaining I/O and memory management as safe facilities the runtime provides. It
is written for agents to read and write, not humans.

Smallness and purity describe L0 as it stands, not promises about what it stays.
Both are revisable; `spec/L0.md` names what currently rests on purity so the
cost of revising it can be read rather than guessed.

You are the primary author of L0 code here, and also the one who changes the
language. **There is no L0 in your training data**, so familiarity cannot
substitute for reading the spec and running the checker.

## Invariants

**[spec/L0.md](spec/L0.md) is the only source of truth about L0.** Not this
file, not the tests, not `stage0/l0i.c`. If an implementation and the spec
disagree, the implementation is wrong. If the spec is silent, that silence is
the bug, and the fix belongs in the spec.

**Never state that L0 code works without running `tools/l0check` on it.** Code
that looks plausible is routinely invalid, because L0 is not any language you
have seen.

**`tools/test.sh` and `tools/test.sh --compiled` must both be green before any
change is done.** No exceptions for small changes.

**`stage0/l0i.c` is frozen. Do not extend it.** It is no longer part of the
bootstrap. It is kept as an independent implementation so the compiled suite
has an oracle that is not the code under test, and editing it to agree with
the compiler destroys exactly that.

**`--bless` overwrites the definition of correct.** Use it only for a deliberate
change, and always read the `git diff` afterward. It is refused together with
`--compiled`, because blessing the compiled suite from compiler output would
remove the only independent check on the compiler.

**Never hand-edit generated files.** Anything under `build/` is reproducible
from source. `bootstrap/stage2.ll`, once it exists, is compiler output and is
replaced only by a successful bootstrap.

**Record language decisions in [spec/changelog.md](spec/changelog.md).** The
spec says what L0 is; the changelog says why. The reasoning is what becomes
unrecoverable.

## When L0 cannot express something

**Change L0 rather than writing around it.** A workaround that ships hides the
limitation that should have shaped the language. Say what could not be written,
then make the change that lets it be written.

A change is earned by code: L0 in this repository that it makes possible, or
makes harder to get wrong. The spec changes first, then the changelog, then the
compiler and its tests. The `l0-bootstrap` skill has the order in full.

## Skills

Read the matching skill before starting these tasks. They contain the specifics
that this file deliberately omits.

- **`l0-code`** — reading, writing, or editing any `.l0` file
- **`l0-bootstrap`** — changing the language, building, testing, or debugging
  a broken bootstrap
- **`l0-roadmap`** — planning work, picking what to do next, tracking status in
  `roadmap/`, or delegating research and L0 programs to subagents

## Layout

```
spec/          L0.md (the language) and changelog.md (why it is that way)
runtime/       l0rt.ll, the runtime every compiled program links, as LLVM IR
compiler/      the L0 compiler, written in L0
bootstrap/     stage2.ll, the checked-in seed the compiler is built from
stage0/        frozen C interpreter, kept only as a differential oracle
tests/         backend (hand-written IR), lang (must run), check (must fail),
               compiler (stage tests for the compiler itself), io (what
               stage 0 cannot run, with hand-written expectations), unit
               (tests written with l0 test)
tools/         build.sh, test.sh, bootstrap.sh, l0c, l0check, l0ll
seeds/         the original seed spec, kept for history, superseded by spec/
roadmap/       plans and status for work in progress (see l0-roadmap)
```

## Two traps specific to this project

**Quadratic output.** Building output by appending is quadratic; it passes every
small test and then hangs on real input. Accumulate in reverse and reverse once.
This is the most likely way to lose a day here.

**Using a language feature in the compiler too early.** The compiler must be
able to compile its own source. Shipping support for a feature and the first use
of that feature in one change produces a compiler that nothing can build. Split
it into two bootstrapped steps; see the `l0-bootstrap` skill.
