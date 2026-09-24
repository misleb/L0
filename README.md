# L0

A statically typed language, compiled to native code through LLVM, that an AI
agent is evolving for its own use.

L0 began with a single goal, **to compile itself**, and reached it. That goal
shaped everything in the language as it stands, and it remains the one
property no change may cost. It no longer decides what comes next.

## What L0 aims to be

**Compiled.** An L0 program becomes machine code; nothing is interpreted when
it runs. That is the one sense in which L0 aims to be fast. Emitting LLVM IR
hands the low-level work, such as tail calls, inlining, and register
allocation, to LLVM, so L0 does not implement optimizations of its own. Beyond
being compiled, performance is not a goal, and speed alone does not justify a
change.

**General purpose.** L0 was expressive enough for exactly one program: its own
compiler, which is a pure function from bytes to bytes. The aim now is a
language that can express ordinary programs, so its limits can be pushed from
inside it. Memory management and I/O come first. Today memory is never freed,
and a program's only contact with the world is one read of stdin and one write
to stdout, both done by a runtime written in LLVM IR. No C source goes into a
compiled program any more; libc stays, as the interface to the operating
system, since on macOS it is the only supported one. The direction now is for
L0 to express allocation and I/O itself.

**Written for agents, not for human readers.** L0 does not aim to be pleasant
for humans to read. Its reader and writer is an agent, so what counts is
whether code comes out correct and whether the checker catches it when it does
not. Brevity and familiarity count for little.

## The experiment

The code is written primarily by a coding agent that has never seen L0,
because L0 did not exist when the model was trained. There is no corpus to
imitate, so a sufficiently precise specification, a handful of examples, a few
well-defined skills and rules, and a fast validation loop have to take the
place of familiarity. The specification is not documentation here; it is the
substrate.

The question is how far that goes, and what kind of language an agent evolves
when it is both the one using the language and the one changing it.

## Status

**L0 compiles itself.** The compiler is written in L0, covers all of L0 v1,
and reaches a byte-identical self-compilation fixpoint. With `stage0/` removed
entirely, the checked-in seed rebuilds the compiler from source and the result
works.

- `spec/L0.md` — L0 v1, complete
- `runtime/l0rt.ll` — allocation, host I/O, and the entry point, as LLVM IR
  calling libc
- `compiler/*.l0` — lexer, parser, checker, and emitter, **written in L0**
- `bootstrap/stage2.ll` — the compiler, compiled, as checked-in LLVM IR text
- `stage0/l0i.c` — an interpreter in C, now **frozen**: no longer part of the
  bootstrap, kept as an independent oracle for the differential suite
- `tests/` — 56 golden test cases, plus 51 run again through the compiler

## Quick start

```bash
tools/build.sh        # needs LLVM; set LLVM_PREFIX if not /opt/homebrew/opt/llvm
tools/test.sh         # all suites
tools/test.sh --compiled   # the differential suite, described below
```

## Installing

```bash
tools/install.sh --prefix ~/.local     # then put ~/.local/bin on PATH
```

This needs `clang` and nothing from L0. **Installing L0 does not require an
existing L0 compiler**, which is the whole point of checking in
`bootstrap/stage2.ll`.

**No C is compiled, at install or ever.** Installing assembles two files of
LLVM IR text:

- `runtime/l0rt.ll`, the runtime, becomes `lib/l0/libl0rt.a`
- `bootstrap/stage2.ll`, the compiler, is linked into `lib/l0/l0c`

`l0 build` links the prebuilt archive into your program. You can delete
`runtime/`, `compiler/`, and `lib/` from a checkout and an installed `l0`
keeps working.

`clang` is still invoked on every build, but only as an assembler and linker
for LLVM IR. GCC has no LLVM IR frontend, so it cannot do that job. Removing
the dependency entirely would mean emitting machine code directly, which means
instruction selection, register allocation, and object-file writing, all in
L0.

Every compiled L0 program links against the runtime, because L0 has no
pointers, no allocation, and no I/O of its own: it cannot express `cons`
allocating a cell, or reading stdin, or running on a large stack and reporting
exhaustion as an error. The runtime is hand-written IR that calls libc, the
same text on every host. Self-hosting means the compiler is written in L0; it
does not mean the system is built from L0 alone. Closing that gap, so that L0
expresses its own allocation and I/O, is one of the goals above.

```bash
l0 check prog.l0          # type check
l0 run   prog.l0 < input  # build and run
l0 build prog.l0 -o prog  # produce an executable
```

Several files are compiled together, since L0 has no module system, and
diagnostics name the file they came from:

```
$ l0 check util.l0 main.l0
main.l0:2:3: error: argument 1 of double must be int, but this is bool
```

## Starting a project

L0 has no package manager and no module system, so `l0 init` scaffolds
everything a project needs, including what an AI agent needs to write L0 at
all:

```bash
l0 init myproject
```

```
AGENTS.md                           always-on invariants
.cursor/skills/l0-code/SKILL.md     how to read, write, and edit L0
l0/L0.md                            the language specification
l0/examples.l0                      worked examples, all of them compiling
l0/prelude.l0                       the standard library, for reference
```

The specification and examples are copied in rather than linked, because an
agent has no L0 in its training data and the specification has to be readable
in the project itself. `lib/examples.l0` is compiled by this repository's own
test suite, so the examples a newcomer reads cannot rot.

## How L0 grows

The agent that writes L0 in this repository is also the one that changes it.
When L0 cannot express something, the answer is to change L0, not to write
around it.

That replaces an earlier arrangement, in which projects elsewhere used an
installed L0, treated it as read-only, and filed requests back here. It was
too slow, and it taught the wrong reflex: an agent that cannot change the
language works around the limitation, the workaround ships, and the pressure
that should have shaped the language is lost. The compiler itself still
carries nine near-identical result types for want of generics, because under
that arrangement a cost paid once per use site never justified a change.

A change still has to be earned by code: L0 in this repository that it makes
possible, or makes harder to get wrong. The spec changes first. `spec/L0.md`
states the rule, `spec/changelog.md` records why, and the compiler follows.
Using a new feature inside the compiler itself has to wait one bootstrap, for
reasons the "Building the compiler from a fresh clone" section below explains.

## The standard library

`lib/prelude.l0` is linked into every program automatically. It is the same
file the compiler itself is built with, so it is exercised continuously rather
than maintained separately.

It matters more than it might sound: L0 has no `append`, no `length`, and no
way to render an integer as text among its builtins. Without a prelude, every
program reimplements decimal formatting, and gets the most-negative-integer
case wrong.

Linking it into everything costs nothing, in either of the two senses that
would otherwise limit how far it can grow.

It costs no space. `main` is the only function emitted with external linkage,
so LLVM deletes every prelude function a program does not call: a hello-world's
object file is 1168 bytes rather than the 10704 it took when all 30 of them
survived.

It costs no names either. The prelude is a separate group of names from the
program, so defining your own `length` is legal — yours is used throughout your
program, while the prelude goes on calling its own:

```
(def is_digit ((c int)) bool false)        ; shadows the prelude's

(def main ((input (list int))) int
  (if (is_digit 55) -1 (int_prefix "77" 0)))   ; prints 77, not -1
```

That matters because it is what makes adding to the prelude safe. Before it,
every new prelude function was a potential breaking change for programs that
had already used the name. Spec section 7.1 has the rule and
`spec/changelog.md` has the reasoning, including why this is two groups of
names rather than a module system.

## What L0 cannot do yet

A program is a pure function from stdin bytes to stdout bytes: there are no
files, no command-line arguments, no network, no clock, and no environment.
Memory is never freed, so it is proportional to total allocation rather than
to live data. Lists are the only data structure, so indexing is O(n), and
there are no arrays, maps, floats, modules, or higher-order functions.

None of these was ruled out. Each is absent because self-compilation never
demanded it, and a general-purpose L0 will. Memory management and I/O come
first.

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

This signature is what made self-hosting tractable. A compiler is a function
from source bytes to output bytes, so **L0 needed no I/O, no strings, and no
module system to compile itself** — only enough expressiveness to compute one
byte list from another. The self-hosting compiler emits LLVM IR
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
tools/build.sh                                  # the runtime, and stage 0
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
runtime/       l0rt.ll, the runtime: allocation, host I/O, entry point
compiler/      the L0 compiler, written in L0
lib/           prelude.l0 (the standard library), examples, and the files
               `l0 init` copies into a new project
bootstrap/     stage2.ll, the checked-in seed the compiler is built from
stage0/        frozen C interpreter, kept only as a differential oracle
tests/         backend (hand-written IR), lang (must run), check (must fail),
               compiler (stage tests for the compiler itself)
tools/         l0 (the driver), install.sh, build.sh, test.sh, bootstrap.sh
seeds/         the original seed spec, superseded by spec/
roadmap/       plans and status for work in progress; never knowledge about L0
.cursor/skills/  agent instructions for developing L0 itself
```

The skills under `.cursor/skills/` are for working *on* L0 and refer to the
compiler sources and test suite. Those under `lib/skills/`, which `l0 init`
installs, are for working *in* L0 and refer only to files a project has.
When writing L0 here teaches something about writing L0 anywhere, the shipped
skill is updated in the same change.

`spec/changelog.md` is worth reading before the spec if you want to know why L0
is shaped the way it is rather than merely what shape it has.

## Requirements

LLVM (for `clang`) and a POSIX shell. No other dependencies, and deliberately
so: `int` is 64-bit rather than arbitrary precision specifically to avoid
needing a bignum library before the first program could run.
