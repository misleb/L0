---
name: l0-bootstrap
description: Build, test, and bootstrap the L0 toolchain, and diagnose self-compilation fixpoint failures where stage2.ll and stage3.ll differ. Use when running the build or test suite, investigating a broken bootstrap, or debugging nondeterministic compiler output.
---

# Building and bootstrapping L0

## Commands

```bash
tools/build.sh                  # runtime objects and build/l0i
tools/test.sh                   # all suites; must be green before anything is done
tools/test.sh NAME              # only tests whose name contains NAME
tools/test.sh --bless [NAME]    # overwrite expectations with current output
tools/l0check FILE.l0 ...       # type check
tools/l0ll FILE.ll OUT          # link generated IR against the runtime
build/l0i run FILE.l0 ... < in  # run a program
tools/bootstrap.sh              # self-compile and check the fixpoint
tools/bootstrap.sh --refresh-seed   # also install the result as bootstrap/stage2.ll
```

`LLVM_PREFIX` overrides the LLVM location (default `/opt/homebrew/opt/llvm`).
`L0_STACK_MB` sets the stack for an L0 program (default 512, good for roughly
1.5 million recursive frames).

**`--bless` overwrites the expectations that define correctness.** Only use it
after a deliberate behavior or wording change, and always read the resulting
`git diff` to confirm every change was intended. Blessing a regression is
silent and converts a caught bug into a permanent one.

## The pieces

- `spec/L0.md` — the only source of truth
- `runtime/l0core.c`, `runtime/l0rt.c` — **permanent.** Value representation,
  allocation, host I/O. Shared with stage 0 so the interpreter and compiled
  code can never disagree about what a value is.
- `stage0/l0i.c` — **disposable.** Interpreter, deleted once the fixpoint holds.
- `compiler/*.l0` — the real L0 compiler, written in L0
- `tests/backend/*.ll` — hand-written IR pinning down the ABI in spec section 10

## The bootstrap chain

The compiler is a byte function: L0 source in, LLVM IR text out. Self-hosting is
verified by a fixpoint, not by judgment.

```
stage0 (C interpreter) + compiler.l0  ->  stage1.ll  ->  stage1
stage1 + compiler.l0                  ->  stage2.ll  ->  stage2
stage2 + compiler.l0                  ->  stage3.ll

stage2.ll must equal stage3.ll, byte for byte.
```

`stage1.ll` and `stage2.ll` **are expected to differ**, because stage 0 and
`compiler.l0` are different programs that emit different but equivalent IR. Only
the stage2/stage3 comparison means anything. Do not try to make stage1 and
stage2 match.

Once the fixpoint holds, `stage2.ll` is checked in as `bootstrap/stage2.ll` and
`stage0/` is deleted. From then on the seed builds the compiler, and L0 has one
implementation.

## Building from a fresh clone after stage 0 is gone

`bootstrap/stage2.ll` is LLVM IR **text**, so `clang` alone turns it into a working
compiler. That is what makes deleting stage 0 safe: the seed is a compiler you
can build without already having one. `tools/bootstrap.sh` does all of this,
but the steps are worth knowing:

```bash
tools/build.sh                                  # the C runtime
tools/l0ll bootstrap/stage2.ll build/l0c-seed        # a compiler, from text alone
cat compiler/*.l0 | build/l0c-seed > build/stage1.ll
tools/l0ll build/stage1.ll build/l0c            # the compiler, from source
```

The compiler reads source on stdin and writes IR on stdout, and L0 has no
module system, so `cat` is the whole of linking the source. Glob order is
lexicographic and therefore stable, which matters because the fixpoint compares
bytes.

## Two constraints the seed imposes

**The seed must be refreshed between the two steps of a feature addition,** not
after both. See the `l0-evolve` skill; `tools/bootstrap.sh` reports when the
seed has gone stale.

**The runtime interface is effectively append-only.** The seed contains
`declare i64 @l0_cons(i64, i64)` and its siblings by name, so renaming or
removing anything in spec section 10.3 breaks every existing seed. The
interface may gain functions freely; losing one requires cutting a new seed in
the same change.

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
for a construct its own source uses. This is the failure the two-step rule in
the `l0-evolve` skill exists to prevent: support for a feature must ship and be
bootstrapped *before* any use of that feature. Check whether a recent change
started using something the previous compiler could not compile, and split it
into two steps.

If a stage builds but crashes with `stack exhausted`, raise `L0_STACK_MB` to
confirm that depth is the real cause before assuming it is a bug, then consider
whether the offending function should be tail recursive.

If a stage builds but appears to hang on `compiler.l0` while passing all small
tests, suspect quadratic output building. See the performance rule in the
`l0-code` skill: output must be accumulated in reverse and reversed exactly
once.
