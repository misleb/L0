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

Phase 1 is complete. The language is specified, runs, and is tested. No L0
compiler has been written yet.

- `spec/L0.md` — L0 v1, complete
- `runtime/` — value representation, allocation, and host I/O, in C
- `stage0/l0i.c` — an interpreter for all of L0 v1, in C, deliberately
  disposable
- `tests/` — 45 golden test cases, 115 in-language assertions
- `compiler/` — not started

## Quick start

```bash
tools/build.sh        # needs LLVM; set LLVM_PREFIX if not /opt/homebrew/opt/llvm
tools/test.sh         # all suites
```

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

`stage1.ll` and `stage2.ll` differ, because stage 0 and `compiler.l0` are
different programs emitting different but equivalent IR. The stage2/stage3
identity is the one that means something: the compiler maps its own source to
exactly the compiler that produced it.

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
