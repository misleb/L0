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
inside it. I/O and memory management come first, as safe facilities the
runtime provides rather than raw memory in L0 code, so that the checker can
still catch what goes wrong. A program can already read and write as it goes,
open files, and read its command-line arguments, and memory is reclaimed by
reference counting, so a program that streams runs in constant memory. Opening
a file returns a data type whose failure case `match` forces the program to
handle. The runtime is LLVM IR, and no
C source goes into a compiled program; libc stays, as the interface to the
operating system, since on macOS it is the only supported one.

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

**L0 compiles itself.** The compiler is written in L0, covers all of L0 as
`spec/L0.md` describes it, and reaches a byte-identical self-compilation
fixpoint. With `stage0/` removed entirely, the checked-in seed rebuilds the
compiler from source and the result works.

- `spec/L0.md` — the language, and the only specification of it; changes are
  recorded in `spec/changelog.md` rather than as numbered versions
- `runtime/l0rt.ll` — allocation and reference counting, host I/O, the clock,
  and the entry point, as LLVM IR calling libc
- `compiler/*.l0` — lexer, parser, checker, and emitter, **written in L0**
- `bootstrap/stage2.ll` — the compiler, compiled, as checked-in LLVM IR text
- `stage0/l0i.c` — an interpreter in C, now **frozen**: no longer part of the
  bootstrap, kept as an independent oracle for the differential suite
- `tests/` — golden test cases held to the stage-0 interpreter, and a compiled
  suite that runs them again through the compiler, along with the programs
  stage 0 cannot run; `tools/test.sh` and `tools/test.sh --compiled` print
  how many

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

- `runtime/l0rt.ll`, the runtime, becomes `lib/l0/l0rt.o`, as LLVM bitcode
- `bootstrap/stage2.ll`, the compiler, is linked into `lib/l0/l0c`

`l0 build` links the prebuilt runtime into your program with link-time
optimization, so the runtime's small functions are inlined into it. You can delete
`runtime/`, `compiler/`, and `lib/` from a checkout and an installed `l0`
keeps working.

`clang` is still invoked on every build, but only as an assembler and linker
for LLVM IR. GCC has no LLVM IR frontend, so it cannot do that job. Removing
the dependency entirely would mean emitting machine code directly, which means
instruction selection, register allocation, and object-file writing, all in
L0.

Every compiled L0 program links against the runtime, because L0 has no
pointers and no raw memory: it cannot express `cons` allocating a cell, or a
buffered read of stdin, or running on a large stack and reporting exhaustion
as an error. The runtime is hand-written IR that calls libc, the same text on
every host. Self-hosting means the compiler is written in L0; it does not mean
the system is built from L0 alone, and by choice it will not: L0 gains
facilities the runtime implements safely, rather than the primitives to write
the runtime itself. `spec/changelog.md` has the reasoning, under "The route to
memory management and I/O".

```bash
l0 check prog.l0          # type check
l0 test  prog_test.l0     # run every (def test_NAME () int ...), as TAP
l0 run   prog.l0 < input  # build and run
l0 build prog.l0 -o prog  # produce an executable
```

`l0 test` finds the tests itself, builds once, and runs each test in its own
process, so a runtime error fails only its own test. Assertions show what was
computed and what was expected; a test can also expect a particular runtime
error, compare against a golden file (`--bless` rewrites them), or check a
property over seeded pseudo-random inputs. `lib/test.l0` is the library and
`lib/examples_test.l0` the worked examples.

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
```

Those two are all it copies, because an agent's environment needs them as
files. Everything else an agent reads comes from the installed toolchain, so
it always describes the compiler that builds the project, however long ago
the project was made:

```bash
l0 spec --path          # the language specification
l0 doc                  # the standard library: every function and type
l0 doc next_line        # one of them in full
l0 examples --path      # worked examples, and tests of them
```

`l0 doc` reads the library's own documentation comments, so it grows with the
library and cannot disagree with it. `lib/examples.l0` is compiled by this
repository's own test suite, so the examples a newcomer reads cannot rot.

## How L0 grows

The agent that writes L0 in this repository is also the one that changes it.
When L0 cannot express something, the answer is to change L0, not to write
around it.

That replaces an earlier arrangement, in which projects elsewhere used an
installed L0, treated it as read-only, and filed requests back here. It was
too slow, and it taught the wrong reflex: an agent that cannot change the
language works around the limitation, the workaround ships, and the pressure
that should have shaped the language is lost. Under that arrangement a cost
paid once per use site never justified a change, which is how L0 went so long
without type parameters.

They exist now, for data types and functions alike, and the compiler is
written with them too. For a while it could not be: the frozen stage-0
interpreter ran the compiler, for `tools/l0check` and the compiler's stage
tests, and knows no type parameters, so the compiler carried near-identical
result types and a reversing helper per element type. The tools now build the
compiler with the seed instead, so the compiler and `lib/prelude.l0` may use
anything the seed compiles, and the copies are gone.

A change still has to be earned by code: L0 in this repository that it makes
possible, or makes harder to get wrong. The spec changes first. `spec/L0.md`
states the rule, `spec/changelog.md` records why, and the compiler follows.
Using a new feature inside the compiler itself has to wait one bootstrap, for
reasons the "Building the compiler from a fresh clone" section below explains.

## The standard library

`lib/prelude.l0` and `lib/io.l0` are linked into every program automatically,
and `l0 test` adds `lib/test.l0`. Together they are the prelude of spec section
7.1, a group of names separate from the program's. `l0 doc` lists everything
in them.

The first two files split by whether a definition does I/O.
`lib/prelude.l0` is part of the compiler too: the compiler is built from it
and `compiler/*.l0`, so it is exercised continuously rather than maintained
separately, and it holds what the compiler can use: `rev`, `rev_onto`,
`append`, `length`, `any_eq`, `index_of`, and `array_resize`, which take type
parameters and so work on every element type, `Option` and `Result`, and the
byte-string helpers. `lib/io.l0` holds the I/O wrappers, including reading a
whole input into `bytes` with `read_input`, which the compiler does not need.

It matters more than it might sound: L0 has no `append`, no `length`, and no
way to render an integer as text among its builtins. Without a library, every
program reimplements decimal formatting, and gets the most-negative-integer
case wrong.

Linking it into everything costs nothing, in either of the two senses that
would otherwise limit how far it can grow.

It costs no space. Only `main`'s entry point and one global that describes it
need external linkage (spec section 10.2), and every other function is emitted
internal, so LLVM deletes every library function a program does not call. A
hello-world built with the library is the same size as one built with
`--no-prelude`.

It costs no names either. Because the library is a separate group, defining
your own `length` is legal — yours is used throughout your program, while the
library goes on calling its own:

```
(def is_digit ((c int)) bool false)        ; shadows the prelude's

(def main ((input (list int))) int
  (if (is_digit 55) -1 (int_prefix "77" 0)))   ; prints 77, not -1
```

Types and constructors are grouped the same way, so a program that declares
its own `Ok` or `Some` keeps it beside the library's `Result` and `Option`.
That matters because it is what makes adding to the library safe. Before it,
every new library name was a potential breaking change for programs that
had already used the name. Spec section 7.1 has the rule and
`spec/changelog.md` has the reasoning, including why this is two groups of
names rather than a module system.

## What L0 cannot do yet

A program can read and write its standard streams and files, read its
command-line arguments, and time itself on a monotonic clock, but there is no
network, no environment, and no wall-clock date.

Memory is freed by reference counting. A whole-input `main` still receives its
input as a list built in full before it starts, a cons cell per byte, but a
program need not take its input that way: a streaming `main` can read it with
`read_input` from the library, or the `read_bytes` builtin, into `bytes`,
which holds about one byte per byte. Arrays give constant-time indexing, and
update in place when nothing else holds them.

Data types and functions take type parameters, so one `Option`, `Result`, or
`rev` serves every element type, and `eq` compares two values of any type
by what they hold, so a membership test or a lookup by key is written once.
But only integers can be ordered, and there are no function values to pass
a comparison in, so a sort is still written once per element type. Nor are
there maps, floats, modules, or mutable state.

None of these was ruled out. Each is absent because self-compilation never
demanded it, and a general-purpose L0 will. Memory management and I/O came
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

Stage 0 runs programs, never the compiler's own source. `tools/l0check`,
`tools/l0c`, and the compiler's stage tests in `tests/compiler`, which link
that source, use the compiler as the seed builds it from the current
`lib/prelude.l0` and `compiler/*.l0`, rebuilt whenever they change. So the
compiler can be written in anything the seed compiles, and its stage tests'
expectations are its own output, read in the `git diff` when blessed.

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

Five built-in types (`int`, `bool`, `(list T)`, `(array T)`, and `bytes`),
user-declared tagged unions, no loops, no mutation, and no function values.
Iteration is recursion, and a function's body is a single expression.

```
(data Tree
  (Leaf int)
  (Branch Tree Tree))

(def sum_tree ((t Tree)) int
  (match t
    ((Leaf n)     n)
    ((Branch l r) (add (sum_tree l) (sum_tree r)))))
```

Data types and functions may take type parameters. A call finds what each
stands for from its arguments' types, so no call writes them:

```
(data (Option T)
  (None)
  (Some T))

(def (rev_onto T) ((xs (list T)) (acc (list T))) (list T)
  (if (is_empty xs)
      acc
      (rev_onto (tail xs) (cons (head xs) acc))))
```

A program can take its whole input at once: the host reads standard input
into a list of bytes, applies `main`, and writes the result.

```
(def main ((input (list int))) (list int))
```

Or it can stream, reading and writing as it goes with `read_byte` and
`write_byte`, and returning its exit status:

```
(def echo () int
  (let b (read_byte)
    (if (lt b 0)
        0
        (let w (write_byte b) (echo)))))

(def main () int
  (echo))
```

That one copies any amount of input in about a megabyte of memory, and a
prompt written that way appears before the program waits for the answer.

The first signature is what made self-hosting tractable. A compiler is a function
from source bytes to output bytes, so **L0 needed no I/O, no strings, and no
module system to compile itself** — only enough expressiveness to compute one
byte list from another. The self-hosting compiler emits LLVM IR
as text, which `clang` then assembles, so L0 never needs to know about object
files or linking either.

## How self-hosting is verified

Not by judgment, but by a byte-for-byte fixpoint:

```
start + compiler source   ->  stage1.ll  ->  stage1
stage1 + compiler source  ->  stage2.ll  ->  stage2
stage2 + compiler source  ->  stage3.ll

stage2.ll == stage3.ll
```

The compiler source is `lib/prelude.l0` and `compiler/*.l0`, and the start is
the checked-in seed, `bootstrap/stage2.ll`. The stage2/stage3 identity is the
one that means something: the compiler maps its own source to exactly the
compiler that produced it.

The first seed was cut by starting from the stage-0 interpreter instead. Then
all three stages were byte-identical, because the interpreter ran the same
source that stage 1 was compiled from, so both computed the same pure function
of the same input, and `stage1.ll == stage2.ll` was an extra check. That
equality would not hold if the start were a separate compiler emitting
equivalent but differently-shaped IR. Since then the bootstrap has started
from the seed, so the language grows with no host-language work at all, and
`stage0/` is kept, frozen, only as the oracle described above.

Run the chain with:

```bash
tools/bootstrap.sh
```

## Building the compiler from a fresh clone

The bootstrap entry point is `bootstrap/stage2.ll`. That file is LLVM IR
**text**, so `clang` alone turns it into a working compiler — which is why the
interpreter is no longer needed to build anything. The seed is a
compiler you can build without already having a compiler, and it needs no L0
tooling, no interpreter, and no prebuilt binary.

```bash
tools/build.sh                                  # the runtime, and stage 0
tools/l0ll bootstrap/stage2.ll build/l0c-seed        # a compiler, from text alone
cat lib/prelude.l0 compiler/*.l0 | build/l0c-seed | tail -n +2 > build/stage1.ll
tools/l0ll build/stage1.ll build/l0c            # the compiler, from its source
```

`cat` is the whole of linking, because L0 has no module system and declaration
order does not matter. The compiler is built with `lib/prelude.l0`, as every
program is, and `tail` drops the first line of its output, a tag saying
whether what follows is IR or diagnostics. `tools/bootstrap.sh` does all of
the above and then verifies the fixpoint.

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
runtime/       l0rt.ll, the runtime: allocation, reference counting, host
               I/O, the clock, entry point
compiler/      the L0 compiler, written in L0
lib/           the standard library (prelude.l0, io.l0, test.l0), examples,
               and the AGENTS.md and skill `l0 init` copies into a project
bootstrap/     stage2.ll, the checked-in seed the compiler is built from
stage0/        frozen C interpreter, kept only as a differential oracle
tests/         backend (hand-written IR), lang (must run), check (must fail),
               compiler (stage tests for the compiler itself), io (what
               stage 0 cannot run, with hand-written expectations), unit
               (tests written with l0 test)
tools/         l0 (the driver), install.sh, build.sh, test.sh, bootstrap.sh
seeds/         the original seed spec, superseded by spec/
roadmap/       plans and status for work in progress; never knowledge about L0
.cursor/skills/  agent instructions for developing L0 itself; .claude/skills
                 links to it for Claude Code
```

The skills under `.cursor/skills/` are for working *on* L0 and refer to the
compiler sources and test suite. Those under `lib/skills/`, which `l0 init`
installs, are for working *in* L0 and refer only to what a project has: its
own files and the `l0` commands.
When writing L0 here teaches something about writing L0 anywhere, the shipped
skill is updated in the same change.

`spec/changelog.md` is worth reading before the spec if you want to know why L0
is shaped the way it is rather than merely what shape it has.

## Requirements

LLVM (for `clang`) and a POSIX shell. No other dependencies, and deliberately
so: `int` is 64-bit rather than arbitrary precision specifically to avoid
needing a bignum library before the first program could run.
