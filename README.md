# L0

A small, pure, statically typed language with exactly one goal: **to compile
itself.**

The goal is the point. L0 does not aim to be fast, general, or pleasant for
humans. It aims to be expressive enough to express its own compiler, and the
gap between what it can do and what that requires is what drives every decision
about which features to add next.

L0 is also an experiment in a second sense: the code is written primarily by a
coding agent that has never seen L0, because L0 did not exist when the model was
trained. There is no corpus to imitate, so a sufficiently precise specification
plus a fast validation loop has to take the place of familiarity. The
specification is not documentation here; it is the substrate.

## Status

**L0 compiles itself.** The compiler is written in L0, covers all of L0 v1,
and reaches a byte-identical self-compilation fixpoint. With `stage0/` removed
entirely, the checked-in seed rebuilds the compiler from source and the result
works.

- `spec/L0.md` — L0 v1, complete
- `runtime/` — value representation, allocation, and host I/O, in C
- `compiler/*.l0` — lexer, parser, checker, and emitter, **written in L0**
- `bootstrap/stage2.ll` — the compiler, compiled, as checked-in LLVM IR text
- `stage0/l0i.c` — an interpreter in C, now **frozen**: no longer part of the
  bootstrap, kept as an independent oracle for the differential suite
- `tests/` — 52 golden test cases, plus 47 run again through the compiler

## Quick start

```bash
tools/build.sh        # needs LLVM; set LLVM_PREFIX if not /opt/homebrew/opt/llvm
tools/test.sh         # all suites
tools/test.sh --compiled   # the differential suite, described below
```

Compile a program with the L0 compiler and run it. Paths are relative to
wherever you are, so this works from outside the repository:

```bash
/path/to/newlang/tools/l0c hello.l0 > hello.ll
/path/to/newlang/tools/l0ll hello.ll hello
./hello
```

Several files are compiled together, since L0 has no module system.
Diagnostics name the file they came from:

```
$ tools/l0c util.l0 main.l0
main.l0:2:3: error: argument 1 of double must be int, but this is bool
```

## What L0 is not

L0 met its goal and is not a general-purpose language. A program is a pure
function from stdin bytes to stdout bytes: there are no files, no command-line
arguments, no network, no clock, and no environment. There is no garbage
collector, so memory is proportional to total allocation rather than to live
data. Lists are the only data structure, so indexing is O(n), and there are no
arrays, maps, floats, modules, or higher-order functions.

Those are deliberate. Each one is absent because the bootstrap goal never
demanded it, which is the rule recorded in `spec/changelog.md`.

## How the compiler is tested

The strongest signal is differential. `tools/test.sh --compiled` bootstraps
the compiler from source, then re-runs the whole suite through it and compares
against the very same expectations the stage-0 interpreter is held to. The
oracle is an independent implementation rather than expectations written by
whoever wrote the compiler.

This is why `stage0/` still exists after self-hosting. It is frozen — never
extended for new language features, because the moment it is edited to agree
with the compiler it stops being independent. Programs using constructs it
cannot handle simply skip.

`--bless` is refused together with `--compiled`. Blessing the compiled suite
from compiler output would replace the oracle with the code under test, which
is the one mistake that would quietly remove all of this value.

Write a program:

```
(def main ((input (list int))) (list int)
  (cons 104 (cons 105 (cons 10 (nil int)))))
```

Check and run it:

```bash
tools/l0check hello.l0
build/l0i run hello.l0        # prints: hi
```

## What L0 looks like

Three built-in types (`int`, `bool`, `(list T)`), user-declared tagged unions,
no loops, no mutation, no I/O, and no function values. Iteration is recursion;
a program is a single pure expression per function.

```
(data Tree
  (Leaf int)
  (Branch Tree Tree))

(def sum_tree ((t Tree)) int
  (match t
    ((Leaf n)     n)
    ((Branch l r) (add (sum_tree l) (sum_tree r)))))
```

A program has no way to observe anything except the value `main` returns. The
host reads standard input into a list of bytes, applies `main`, and writes the
result:

```
(def main ((input (list int))) (list int))
```

This signature is the whole reason the project is tractable. A compiler is a
function from source bytes to output bytes, so **L0 needs no I/O, no strings,
and no module system to compile itself** — it only needs to be expressive enough
to compute one byte list from another. The self-hosting compiler emits LLVM IR
as text, which `clang` then assembles, so L0 never needs to know about object
files or linking either.

## How self-hosting is verified

Not by judgment, but by a byte-for-byte fixpoint:

```
stage0 (C interpreter) + compiler.l0  ->  stage1.ll  ->  stage1
stage1 + compiler.l0                  ->  stage2.ll  ->  stage2
stage2 + compiler.l0                  ->  stage3.ll

stage2.ll == stage3.ll
```

The stage2/stage3 identity is the one that means something: the compiler maps
its own source to exactly the compiler that produced it.

Here all three stages are byte-identical, because stage 0 is an *interpreter*
running the same `compiler/*.l0` that stage 1 is compiled from. Both compute
the same pure function of the same input, so `stage1.ll == stage2.ll` is an
extra check, and a difference would mean the compiler miscompiled itself. That
equality would not hold if stage 0 were a separate compiler emitting
equivalent but differently-shaped IR.

When that holds, `stage2.ll` is checked in as a bootstrap seed and `stage0/` is
**deleted**. From that point L0 has exactly one implementation, written in
itself, and the language can grow with no host-language work at all.

Run the chain with:

```bash
tools/bootstrap.sh
```

## Building the compiler from a fresh clone

Once `stage0/` is gone, the only bootstrap entry point is `bootstrap/stage2.ll`.
That file is LLVM IR **text**, so `clang` alone turns it into a working
compiler — which is what makes deleting the interpreter safe. The seed is a
compiler you can build without already having a compiler, and it needs no L0
tooling, no interpreter, and no prebuilt binary.

```bash
tools/build.sh                                  # the C runtime
tools/l0ll bootstrap/stage2.ll build/l0c-seed        # a compiler, from text alone
cat compiler/*.l0 | build/l0c-seed > build/stage1.ll
tools/l0ll build/stage1.ll build/l0c            # the compiler, from its source
```

`cat` is the whole of linking, because L0 has no module system and declaration
order does not matter. `tools/bootstrap.sh` does all of the above and then
verifies the fixpoint.

**The seed is frozen, so it only knows the language as it was when it was cut.**
That makes one ordering rule load-bearing: when the compiler gains the ability
to compile a new feature, the seed must be refreshed *before* the compiler
starts using that feature, not after. Refreshing late leaves your own tree
building fine while a fresh clone becomes unbuildable, and no local command
will tell you. `tools/bootstrap.sh --refresh-seed` cuts a new seed, and a plain
`tools/bootstrap.sh` warns when the current one has gone stale.

## Repository layout

```
spec/          L0.md (what the language is) and changelog.md (why)
runtime/       permanent C: values, allocation, host I/O
stage0/        disposable C interpreter
compiler/      the L0 compiler, in L0 (not started)
bootstrap/     checked-in compiler IR, the bootstrap entry point (not yet cut)
tests/         backend (hand-written IR), lang (must run), check (must fail)
tools/         build.sh, test.sh, bootstrap.sh, l0check, l0ll
seeds/         the original seed spec, superseded by spec/
.cursor/skills/  agent instructions for writing L0 and evolving it
```

`spec/changelog.md` is worth reading before the spec if you want to know why L0
is shaped the way it is rather than merely what shape it has.

## Requirements

LLVM (for `clang`) and a POSIX shell. No other dependencies, and deliberately
so: `int` is 64-bit rather than arbitrary precision specifically to avoid
needing a bignum library before the first program could run.
