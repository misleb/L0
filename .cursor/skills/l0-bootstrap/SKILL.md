---
name: l0-bootstrap
description: Change the L0 language, and build, test, and bootstrap the L0 toolchain without breaking self-compilation. Covers the spec-first order of work, the two-step rule for using a new feature inside the compiler, the frozen stage-0 oracle, and diagnosing fixpoint failures where stage2.ll and stage3.ll differ. Use when changing spec/L0.md, adding a builtin, syntax form, or runtime function, altering L0 semantics, running the build or test suite, investigating a broken bootstrap, or debugging nondeterministic compiler output.
---

# Changing, building, and bootstrapping L0

## Commands

```bash
tools/build.sh                  # runtime objects and build/l0i
tools/test.sh                   # all suites; must be green before anything is done
tools/test.sh NAME              # only tests whose name contains NAME
tools/test.sh --bless [NAME]    # overwrite expectations with current output
tools/l0check FILE.l0 ...       # type check
tools/l0ll FILE.ll OUT          # link generated IR against the runtime
tools/l0 run FILE.l0 ... < in   # run a program (build/l0i knows only stage 0's L0)
tools/bootstrap.sh              # self-compile and check the fixpoint
tools/bootstrap.sh --refresh-seed   # also install the result as bootstrap/stage2.ll
tools/linux-test.sh [arm64] [amd64] # both suites on Linux, in a local container
```

Run `tools/linux-test.sh` on any change to the runtime or the emitter, since
LLVM and libc behave differently between hosts in ways macOS alone won't
show. It needs Docker, builds its image from `tools/linux/Dockerfile` the
first time, and tests the working tree as it is, uncommitted changes
included.

`LLVM_PREFIX` overrides the LLVM location (default `/opt/homebrew/opt/llvm`).
`L0_STACK_MB` sets the stack for an L0 program, in megabytes (default 512).
Tail calls use none of it (spec section 8); only nesting of calls that are not
tail calls does.

**`--bless` overwrites the expectations that define correctness.** Only use it
after a deliberate behavior or wording change, and always read the resulting
`git diff` to confirm every change was intended. Blessing a regression is
silent and converts a caught bug into a permanent one.

## The pieces

- `spec/L0.md` — the only source of truth
- `runtime/l0rt.ll` — the runtime every compiled program links: allocation,
  host I/O, the entry point, and stack checks, as LLVM IR calling libc. It
  must stay the same text on every host; its header says what that rules out.
  See the constraints on the runtime interface below before changing it.
- `stage0/l0core.c`, `stage0/l0core.h` — stage 0's value representation and
  host I/O, in C. Compiled programs never link them.
- `compiler/*.l0` — the L0 compiler, written in L0
- `bootstrap/stage2.ll` — the compiler, compiled. The bootstrap entry point.
- `stage0/l0i.c` — **frozen.** No longer part of the bootstrap, and never
  extended for new features. Kept solely as an independent implementation for
  `tools/test.sh --compiled` to judge the compiler against.
- `tests/backend/*.ll` — hand-written IR pinning down the ABI in spec section 10

## The two suites

`tools/test.sh` runs everything through the stage-0 interpreter.
`tools/test.sh --compiled` bootstraps the current compiler from source and
re-runs the same programs through it:

- `tests/lang` — compiled, run, and compared against **the interpreter's**
  expectations, which is what makes it differential
- `tests/compiler` — the compiler's own stage tests, against the same goldens
  both ways, so any divergence between implementations shows up immediately
- `tests/check` — programs that must be rejected, compared against `.cerr`
  files holding the compiler's own wording. What matters is that every
  program the interpreter rejects, the compiler rejects too.

`--compiled` bootstraps first rather than using the checked-in seed, so it
always tests the current compiler. Using the seed would silently test an old
one whenever the seed is stale.

## The bootstrap chain

The compiler is a byte function: L0 source in, LLVM IR text out. Self-hosting is
verified by a fixpoint, not by judgment.

```
stage0 (C interpreter) + compiler.l0  ->  stage1.ll  ->  stage1
stage1 + compiler.l0                  ->  stage2.ll  ->  stage2
stage2 + compiler.l0                  ->  stage3.ll

stage2.ll must equal stage3.ll, byte for byte.
```

When stage 1 comes from the **stage-0 interpreter**, all three stages are
byte-identical, and `tools/bootstrap.sh` checks that. The interpreter runs the
very same `compiler/*.l0` that stage 1 is compiled from, so both compute the
same pure function of the same input, and L0 is deterministic. A difference
between `stage1.ll` and `stage2.ll` therefore means the compiler miscompiled
itself, which is a sharper signal than the fixpoint alone and points at the
construct being emitted where they diverge.

That equality would **not** hold if stage 1 came from a different compiler
emitting equivalent but differently-shaped IR. In general only
`stage2.ll == stage3.ll` is required; `stage1.ll == stage2.ll` is an extra
check this particular bootstrap can afford, and the script only applies it
when the interpreter was used.

Once the fixpoint holds, `stage2.ll` is checked in as `bootstrap/stage2.ll` and
`stage0/` is deleted. From then on the seed builds the compiler, and L0 has one
implementation.

## Building from a fresh clone after stage 0 is gone

`bootstrap/stage2.ll` is LLVM IR **text**, so `clang` alone turns it into a working
compiler. That is what makes deleting stage 0 safe: the seed is a compiler you
can build without already having one. `tools/bootstrap.sh` does all of this,
but the steps are worth knowing:

```bash
tools/build.sh                                  # the runtime, and stage 0
tools/l0ll bootstrap/stage2.ll build/l0c-seed        # a compiler, from text alone
cat compiler/*.l0 | build/l0c-seed > build/stage1.ll
tools/l0ll build/stage1.ll build/l0c            # the compiler, from source
```

The compiler reads source on stdin and writes IR on stdout, and L0 has no
module system, so `cat` is the whole of linking the source. Glob order is
lexicographic and therefore stable, which matters because the fixpoint compares
bytes.

## Changing the language

Changing the language is not the same as changing a program in it. The spec,
the compiler, and the frozen stage-0 interpreter all encode the same rules, and
a disagreement between them breaks the bootstrap in confusing ways.

A change is earned by L0 in this repository that it makes possible, or makes
harder to get wrong. When L0 cannot express something, change L0 rather than
writing around it, and keep the program that hit the limit: it becomes the
test and the changelog's evidence.

**The spec changes first, always.** It is the only source of truth, and an
implementation that runs ahead of it produces code no future agent can justify.

```
1. spec/L0.md        state the new rule precisely
2. spec/changelog.md record what changed and WHY, with the code that needed it
3. compiler/*.l0     lexer, parser, checker, emitter (see the two-step rule)
4. tests/            a passing case and a failing case for every new rule
5. tools/test.sh     green, and tools/test.sh --compiled green
6. tools/bootstrap.sh --refresh-seed, and commit the seed
```

Skipping step 2 is the most common mistake and the most costly, because the
reason a feature exists is exactly what is unrecoverable later.

If the change teaches something about writing L0 in general, update
`lib/skills/l0-code/SKILL.md` and `lib/examples.l0` in the same change, since
those are what `l0 init` gives an agent outside this repository.

### The two-step rule

**To use a new feature inside the compiler's own source, ship the ability to
compile it before you ship any use of it.** Two separate, individually
bootstrapped changes:

```
Step 1    compiler/*.l0 can COMPILE the feature, but uses none of it.
          tools/bootstrap.sh          -- the fixpoint must hold

Step 1b   Install that compiler as the bootstrap seed, and commit it.
          tools/bootstrap.sh --refresh-seed

Step 2    compiler/*.l0 now USES the feature in its own source.
          tools/bootstrap.sh          -- the fixpoint must hold again
```

Doing both at once produces a compiler whose source needs a feature that the
last working compiler cannot compile. Nothing in the chain can then build it,
and the only ways out are hand-editing generated IR or reverting.

**Step 1b is not optional, and its position between the two steps is the whole
point.** The seed can only compile features that existed when it was cut.
Refreshing after step 2 is too late: your working tree keeps building because
it already has a current compiler, while a fresh clone becomes unbuildable.
Nothing you can run locally reveals that.

The same rule applies to *removing* or changing the meaning of a feature, in
reverse: stop using it, bootstrap, refresh the seed, then drop support, then
bootstrap again.

### Stage 0 stays frozen

**Do not extend `stage0/l0i.c` for new language features.** It is kept only as
an independent implementation for `tools/test.sh --compiled` to judge the
compiler against, and it stays independent only as long as nobody edits it to
agree with the compiler. Programs using a new feature cannot run under stage 0;
the compiled suite skips them, and coverage of the old language stays intact.

If the two disagree on something both support, **the spec decides which is
wrong.** If the spec is silent, that is the actual bug, and the fix belongs in
the spec.

### Properties that cost something to break

These restrictions keep the checker simple and every error local, which is
worth more to an agent writing L0 than any keystroke they cost. Breaking one is
allowed, but should buy something substantial, and the changelog should say
what:

- `match` patterns are one level deep with no wildcard, so adding a constructor
  becomes a compile error at every site that must handle it
- there is no type inference, so every expression's type is determined by itself
  and never by context
- `list` and `array` are the only parametric type constructors, and every
  builtin over them takes its element type from an argument, so no
  unification is needed anywhere
- there are no function values, so name resolution is purely syntactic

### Ambiguities

Implementing a change will turn up questions the spec does not answer. Do not
guess silently: settle it in the spec as part of the change, or record it in
`spec/changelog.md` with the question, the decision, and why, so it can be
overruled later.

### Done means

- [ ] `spec/L0.md` states the rule, and nothing in it is now false
- [ ] `spec/changelog.md` says what changed and why
- [ ] `tools/test.sh` passes, including a new failing case per new error
- [ ] `tools/test.sh --compiled` passes
- [ ] the bootstrap fixpoint holds, and the seed is refreshed if the compiler
      learned something

## Constraints the seed imposes

**The seed must be refreshed between the two steps of a feature addition,** not
after both. See the two-step rule above; `tools/bootstrap.sh` reports when the
seed has gone stale.

**The runtime interface is effectively append-only.** The seed contains
`declare i64 @l0_cons(i64, i64)` and its siblings by name, so renaming or
removing anything in spec section 10.3 breaks every existing seed. The
interface may gain functions freely; losing one requires cutting a new seed in
the same change.

**A runtime that relies on something the compiler emits needs a fresh seed in
the same change.** `tools/l0` compiles with the installed compiler, built from
the seed, not from source. When the runtime moved stack-exhaustion reporting
into checks the compiler emits, programs built by the old seed had no checks
and crashed instead of reporting the error. `tools/test.sh --compiled` cannot
see this, because it bootstraps from source first. Check such a change with
`tools/l0 build`, and refresh the seed before committing. In a checkout,
`tools/l0` rebuilds `lib/` by itself when the seed or `runtime/l0rt.ll` is
newer than what it last built.

**The seed pins a range of LLVM versions.** Textual IR is not guaranteed stable
across LLVM major versions. L0 emits close to the most stable possible subset
(`i64`, `alloca`/`load`/`store`, `call`, `br`, `switch`, `icmp`, integer
arithmetic), but `ptr` is opaque-pointer syntax that older LLVM spells `i8*`.
`bootstrap/LLVM-VERSION` records what produced the current seed. If a future LLVM
rejects the seed, the fix is to regenerate it with a version that still parses
it, which means not letting the seed get many years stale.

## When stage2.ll and stage3.ll differ

This means the compiler does not compile itself to itself. There are two causes,
and they need completely different responses, so **identify which one first**:

```bash
diff <(head -c 200000 stage2.ll) <(head -c 200000 stage3.ll) | head -40
```

**Cause 1: nondeterminism.** The compiler's output is not a function of its
input alone. Check by compiling the same input twice with the *same* binary:

```bash
./stage2 < compiler.l0 > a.ll
./stage2 < compiler.l0 > b.ll
cmp a.ll b.ll
```

If those differ, the bug is nondeterminism and nothing else matters until it is
fixed. Something environment-derived is reaching the output: an address, a hash
iteration order, a clock, an environment variable, or a target triple. Spec
section 10.4 forbids all of these. L0 itself is pure and deterministic, so the
cause is almost always a counter seeded from something it should not be.

**Cause 2: a real miscompile.** If the same binary is self-consistent but
stage2 and stage3 disagree, then stage1 and stage2 compiled `compiler.l0`
differently, which means one of them is wrong. Find the first differing line and
map it back to the L0 definition being emitted when it appears. The construct
being compiled at that point is the suspect, and it is usually one the compiler
does not exercise on itself until late.

A useful narrowing trick: the earliest divergence in the file is the one to
chase. Later differences are usually downstream consequences of it, especially
if the compiler numbers temporaries sequentially.

## When the bootstrap fails earlier

If `stage1` cannot compile `compiler.l0` at all, the compiler is missing support
for a construct its own source uses. This is the failure the two-step rule
above exists to prevent: support for a feature must ship and be
bootstrapped *before* any use of that feature. Check whether a recent change
started using something the previous compiler could not compile, and split it
into two steps.

If a stage builds but crashes with `stack exhausted`, raise `L0_STACK_MB` to
confirm that depth is the real cause before assuming it is a bug, then consider
whether the offending function should be tail recursive. A loop that is
already tail recursive and still exhausts the stack is a compiler bug: a tail
call must be emitted as `musttail`, so look for one that is not.
`tests/io/tail_calls` checks the guarantee at `-O0`, where LLVM eliminates no
call on its own.

If a stage builds but appears to hang on `compiler.l0` while passing all small
tests, suspect quadratic output building. See the performance rule in the
`l0-code` skill: output must be accumulated in reverse and reversed exactly
once.
