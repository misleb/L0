# Working in this repository

L0 is a programming language being built in this repository with one goal: to
compile itself. Pursuing that goal is what drives every decision about what the
language should become.

You are the primary author of L0 code here. **There is no L0 in your training
data**, so familiarity cannot substitute for reading the spec and running the
checker.

## Invariants

**[spec/L0.md](spec/L0.md) is the only source of truth about L0.** Not this
file, not the tests, not `stage0/l0i.c`. If an implementation and the spec
disagree, the implementation is wrong. If the spec is silent, that silence is
the bug, and the fix belongs in the spec.

**Never state that L0 code works without running `tools/l0check` on it.** Code
that looks plausible is routinely invalid, because L0 is not any language you
have seen.

**`tools/test.sh` must be green before any change is done.** No exceptions for
small changes.

**`--bless` overwrites the definition of correct.** Use it only for a deliberate
change, and always read the `git diff` afterward.

**Never hand-edit generated files.** Anything under `build/` is reproducible
from source. `seed/stage2.ll`, once it exists, is compiler output and is
replaced only by a successful bootstrap.

**Record language decisions in [spec/changelog.md](spec/changelog.md).** The
spec says what L0 is; the changelog says why. The reasoning is what becomes
unrecoverable.

## Skills

Read the matching skill before starting these tasks. They contain the specifics
that this file deliberately omits.

- **`l0-code`** — reading, writing, or editing any `.l0` file
- **`l0-evolve`** — changing the L0 language itself
- **`l0-bootstrap`** — building, testing, or debugging a broken bootstrap

## Layout

```
spec/          L0.md (the language) and changelog.md (why it is that way)
runtime/       permanent C: value representation, allocation, host I/O
stage0/        disposable C interpreter, deleted once the fixpoint holds
compiler/      the L0 compiler, written in L0
tests/         backend (hand-written IR), lang (must run), check (must fail)
tools/         build.sh, test.sh, l0check, l0ll
seeds/         the original seed spec, kept for history, superseded by spec/
```

## Two traps specific to this project

**Quadratic output.** Building output by appending is quadratic; it passes every
small test and then hangs on real input. Accumulate in reverse and reverse once.
This is the most likely way to lose a day here.

**Using a language feature in the compiler too early.** The compiler must be
able to compile its own source. Shipping support for a feature and the first use
of that feature in one change produces a compiler that nothing can build. Split
it into two bootstrapped steps; see the `l0-evolve` skill.
