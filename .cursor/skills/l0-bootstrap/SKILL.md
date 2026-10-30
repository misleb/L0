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
tools/test.sh --compiled --bless-check [NAME]   # rewrite tests/check's .cerr
tools/l0check FILE.l0 ...       # type check, with the compiler of the current source
tools/l0c FILE.l0 ... > OUT.ll  # compile to IR, with the same compiler
tools/l0ll FILE.ll OUT          # link generated IR against the runtime
tools/l0 run FILE.l0 ... < in   # run a program (build/l0i knows only stage 0's L0)
tools/bootstrap.sh              # self-compile and check the fixpoint
tools/bootstrap.sh --refresh-seed   # also install the result as bootstrap/stage2.ll
tools/linux-test.sh [arm64] [amd64] # both suites on Linux, in a local container
tools/pi5-run PROG.l0 [ARG ...] < in # run on a Pi 5 that boots from TFTP, and print
                                # its serial output; see the script's header
tools/test.sh --virt [NAME]     # the fixpoint, the compiled suite, and
                                # tests/virt on QEMU's virt board, no OS,
                                # then tests/virt and tests/virt/proc as
                                # processes under the harness kernel
tools/bootstrap.sh --virt       # also check the fixpoint's last step there,
                                # and as a process
tools/l0 run --target virt FILE.l0 ... < in   # build and boot on the board
```

NAME is a substring of a test's file name without its directory or
extension, matched in every suite: `bundle_prelude`, not
`compiler/bundle_prelude`, which matches nothing and passes as "0 tests".

LLVM and libc behave differently between hosts, so a change to the runtime
or the emitter is tested on both Linux and macOS. On a macOS host, run
`tools/linux-test.sh` for the Linux half; on a Linux host `tools/test.sh`
is that half already, and macOS is left to a run there, said so in the
item's Log. It needs Docker, builds its image from `tools/linux/Dockerfile`
the first time, and tests the working tree as it is, uncommitted changes
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

- `spec/L0.md`, `spec/runtime.md`, and `spec/boards/` — the only source of
  truth: the language, section 10, and each host's devices, interrupts, and
  layout
- `runtime/l0rt.ll` — the runtime every compiled program links: allocation,
  buffered I/O, and stack checks, as LLVM IR the same on every host. It
  reaches the host only through the `l0_host_` functions of spec 10.3, and
  calls no libc. See the constraints on the runtime interface below before
  changing it.
- `runtime/host-libc.ll` — the host file for macOS and Linux: those
  functions, through libc, and the entry point. It must stay the same text
  on both; its header says what that rules out. A change in it needs
  `tools/linux-test.sh`, as one in `l0rt.ll` does.
- the hosts without an operating system, in parts by who decides them:
  `runtime/bare/board.ll`, what no machine decides of a board's host;
  `runtime/arch/aarch64/boot.ll`, the CPU's part; `runtime/board/
  virt-aarch64.ll` and `.ld`, QEMU's aarch64 virt board and its layout;
  `runtime/dev/`, the drivers a board's part drives its devices with; and
  `runtime/bare/semihost.ll`; and `runtime/bare/absent.ll`, every host
  function as a host lacking its facility gives it (spec 9.2), `weak`, so
  that a host's own part defines only what it has, and a new host function
  gets its absent definition there first. Each target's manifest,
  `runtime/targets/NAME.target`, lists its parts, and `tools/targets.sh`
  builds them into `build/NAME/`; a new board or CPU is a new manifest and
  the parts it lacks, and the tools need no change. There are three boards,
  QEMU's aarch64 and riscv64 virt boards, which `--virt` runs, and the
  Raspberry Pi 5, which has no emulator and runs only on a board, by
  `tools/pi5-run`; a test's expectations for one
  CPU, where they differ, are `<stem>.ARCH.out` and the like, and board
  constants for tests are `tests/virt/board/virt-ARCH.l0`. A change to any
  part, to `l0rt.ll`, or to the emitter needs `tools/test.sh --virt`, which
  checks the fixpoint on each board and runs the compiled suite's programs
  and `tests/virt` there, about six minutes for both
  (`L0_VIRT_ARCHS=riscv64` runs one while iterating). The emitter's
  `fastcc` is load-bearing on riscv64, where LLVM 23 gets a tail call's
  stack words wrong (spec 10.3). A new test that needs files
  or arguments and has no `.sh` script gets a `.host` file saying why, or
  fails there.
- `runtime/bare/proc.ll`, `runtime/arch/aarch64/proc.ll`, and
  `runtime/proc.ld` — the host and layout for a program run as a process by
  a kernel, which makes the system calls of spec 10.3;
  `runtime/freestanding.ll` — the allocator and `mem` functions every host
  without libc links. A change to any of them, or
  to the calls, needs `tools/test.sh --virt`, which runs `tests/virt` again
  as processes, and `tests/virt/proc`, under the kernel hand-written in IR
  in `tests/virt/proc/harness`. That kernel is a test harness, as
  `tests/backend` is: it answers spec 10.3's calls, and a change to them
  changes it too. So does `tests/virt/user/kernel.l0`, the kernel in L0
  that runs `tests/virt` again through the user-mode builtins of spec
  6.13, which the board's host gives, and `tests/virt/proc`'s tests with the
  timer's slices of 6.14. It defines calls of its own (6.15), which its
  header lists, and a `tests/virt/user/NAME.procs` file names the processes
  of a test under it, such as a serial driver and its client. The board's
  host drives the GIC itself, so no test may open it as a region. A `tests/virt` program with a `.board`
  file runs on the board only, never as a process: one that uses user
  mode, which a process has not.
- `stage0/l0core.c`, `stage0/l0core.h` — stage 0's value representation and
  host I/O, in C. Compiled programs never link them.
- `compiler/*.l0` — the L0 compiler, written in L0
- `bootstrap/stage2.ll` — the compiler, compiled. The bootstrap entry point.
- `tools/compiler.sh` — builds `build/l0c-current`, the current
  `lib/prelude.l0` and `compiler/*.l0` compiled once by the seed and linked
  at `-O0`, whenever that source changes. `tools/l0check`, `tools/l0c`, and
  the stage tests in `tools/test.sh` run it, so they always run the compiler
  of the source in the tree.
- `stage0/l0i.c` — **frozen.** No longer part of the bootstrap, and never
  extended for new features. Kept solely as an independent implementation for
  `tools/test.sh --compiled` to judge the compiler against. It runs the
  programs in `tests/lang` and `tests/check`, never the compiler's own source,
  so the compiler and `lib/prelude.l0` may use anything the seed compiles.
- `tests/backend/*.ll` — hand-written IR pinning down the ABI in spec section 10

## The two suites

`tools/test.sh` runs the programs through the stage-0 interpreter, and builds
the compiler's stage tests with the current compiler. `tools/test.sh
--compiled` bootstraps the current compiler from source and re-runs the same
tests through it:

- `tests/lang` — compiled, run, and compared against **the interpreter's**
  expectations, which is what makes it differential
- `tests/compiler` — the compiler's own stage tests, which link its source,
  against the same goldens both ways: built by the seed-built compiler in
  `tools/test.sh`, and by the bootstrapped one in `--compiled`. Their goldens
  are the compiler's own output, and always were, since stage 0 only ran the
  compiler's code when it ran them, so `--bless` blesses them in
  `tools/test.sh` and the `git diff` is the review
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
seed (bootstrap/stage2.ll) + compiler.l0  ->  stage1.ll  ->  stage1
stage1 + compiler.l0                      ->  stage2.ll  ->  stage2
stage2 + compiler.l0                      ->  stage3.ll

stage2.ll must equal stage3.ll, byte for byte.
```

Only `stage2.ll == stage3.ll` is required: the seed is an earlier compiler,
and may emit equivalent but differently-shaped IR, so `stage1.ll` can differ.
`tools/bootstrap.sh` reports the seed stale when it does.

The first seed was cut by starting from the stage-0 interpreter, which ran
the very same `compiler/*.l0`, so all three stages were byte-identical and
`stage1.ll == stage2.ll` was an extra check. That start is gone: stage 0
cannot run a compiler source that uses anything it predates, so the seed is
the only start.

## Building from a fresh clone

`bootstrap/stage2.ll` is LLVM IR **text**, so `clang` alone turns it into a working
compiler. That is why nothing needs stage 0 to build: the seed is a compiler
you can build without already having one. `tools/bootstrap.sh` does all of
this, but the steps are worth knowing:

```bash
tools/build.sh                                  # the runtime, and stage 0
tools/l0ll bootstrap/stage2.ll build/l0c-seed        # a compiler, from text alone
cat lib/prelude.l0 compiler/*.l0 | build/l0c-seed | tail -n +2 > build/stage1.ll
tools/l0ll build/stage1.ll build/l0c            # the compiler, from source
```

The compiler reads source on stdin and writes IR on stdout, after a first line
tagging it as IR or diagnostics, which `tail` drops. L0 has no module system,
so `cat` is the whole of linking the source. Glob order is lexicographic and
therefore stable, which matters because the fixpoint compares bytes.

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
compile it before you ship any use of it.** The compiler's source is
`compiler/*.l0` and `lib/prelude.l0`, so this holds for the prelude too: 0064
added `compare` and 0065 then used it in the prelude's `sort`. Two separate,
individually bootstrapped changes:

```
Step 1    compiler/*.l0 can COMPILE the feature, but neither it nor
          lib/prelude.l0 uses any of it.
          tools/bootstrap.sh          -- the fixpoint must hold

Step 1b   Install that compiler as the bootstrap seed, and commit it.
          tools/bootstrap.sh --refresh-seed

Step 2    compiler/*.l0 or lib/prelude.l0 now USES the feature.
          tools/bootstrap.sh          -- the fixpoint must hold again
```

Doing both at once produces a compiler whose source needs a feature that the
last working compiler cannot compile. Nothing in the chain can then build it,
and the only ways out are hand-editing generated IR or reverting.

**Step 1b is not optional, and its position between the two steps is the whole
point.** The seed can only compile features that existed when it was cut.
Every tool builds the compiler from the checked-in seed (`tools/compiler.sh`
for `tools/l0check`, `tools/l0c`, and the stage tests; `tools/bootstrap.sh`
from `bootstrap/stage2.ll`), so a use of a feature the seed lacks fails at
once, with the seed's diagnostics. What no local command shows is a
refreshed seed left uncommitted: a fresh clone gets the old one. So commit
`bootstrap/stage2.ll` and `bootstrap/LLVM-VERSION` at step 1b.

The same rule applies to *removing* or changing the meaning of a feature, in
reverse: stop using it, bootstrap, refresh the seed, then drop support, then
bootstrap again.

### Stage 0 stays frozen

**Do not extend `stage0/l0i.c` for new language features.** It is kept only as
an independent implementation for `tools/test.sh --compiled` to judge the
compiler against, and it stays independent only as long as nobody edits it to
agree with the compiler. Programs using a new feature cannot run under stage 0;
the compiled suite skips them, and coverage of the old language stays intact.
It judges programs, not the compiler's source: nothing runs `lib/prelude.l0`
or `compiler/*.l0` under it, so neither is held to the L0 it knows.

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
- no unification is needed anywhere: every builtin over `list` and `array`
  takes its element type from an argument, a construction of a parametric
  `data` type takes its type arguments from its arguments or has them
  written, `((None int))`, and a call of a function with type parameters
  takes them from its arguments, which must mention every one (spec 4.1)
- there are no function values, so name resolution is purely syntactic: a
  function is passed only by name to a parameter of function type (spec
  5.7), and a call resolves to such a parameter only where its declared
  type says it is one

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

## Adding a builtin

Every builtin added so far touched the same places; missing one shows up late:

- `spec/L0.md`: section 6's table and the builtin's own subsection;
  section 8's table for a new runtime error. `spec/runtime.md`: 10.3's
  `declare` list and how it is emitted, for a runtime call; the borrowing
  and read-only lists in 10.3 if it reads a counted argument without
  consuming it. `spec/boards/`: a board's devices or interrupts it adds
- `compiler/check.l0`: its name in a builtin group, its arity, and its type
- `compiler/emit.l0`: `io_names` or `rt_names`, `builtin_type` for a result
  that is not `int`, `is_borrowing` if it reads without consuming, and the
  module header's `declare` (`bit_decls`)
- `runtime/l0rt.ll`: the `@l0_` function
- tests: `tests/compiler/check_errors` for arity and type; `bundle_prelude`
  and `emit_tail` re-blessed for the new `declare`, every time
  (`tools/test.sh --bless bundle_prelude`); behaviour in `tests/io` or
  `tests/unit`, since stage 0 is frozen
- a library wrapper in `lib/`, with `tests/io/libdoc/index.txt` regenerated
  by `tools/l0 doc > tests/io/libdoc/index.txt` and its diff read
- the seed refreshed, and `tools/linux-test.sh` for a runtime change

## Constraints the seed imposes

**The seed must be refreshed between the two steps of a feature addition,** not
after both. See the two-step rule above; `tools/bootstrap.sh` reports when the
seed has gone stale.

**`tools/l0` compiles with the seed, not the source in the tree.** It uses
`lib/l0c`, built from `bootstrap/stage2.ll`, and links the working tree's
`lib/`. So until the seed is refreshed, a new builtin is unknown to `tools/l0
run`, `build`, `check`, and `test`, though `tools/test.sh --compiled` passes,
since it points `L0_COMPILER` at the compiler it just built; and once
`lib/io.l0` uses the builtin, every `tools/l0` command but `doc`, `spec`,
`examples`, and `init` fails. Before the refresh, run it as
`L0_COMPILER=build/l0c-current L0_RUNTIME=build/l0rt.o
L0_HOST=build/l0host.o tools/l0 ...` after a `tools/l0check` has built
`build/l0c-current`; `L0_RUNTIME` and `L0_HOST` too, since setting
`L0_COMPILER` skips rebuilding `lib/l0rt.o` and `lib/l0host.o`.

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
`tools/l0` rebuilds `lib/` by itself when the seed, `runtime/l0rt.ll`, or
`runtime/host-libc.ll` is newer than what it last built.

**The host interface is not the seed's to pin.** The `l0_host_` functions
of spec 10.3 are called only by `l0rt.ll` and defined only by a host file,
both linked fresh into every program, so they may change in any change that
updates both, with no new seed. Only the `l0_` functions compiled code
calls are append-only.

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
section 10.4 forbids all of these. L0 is no longer pure, but the compiler is a
whole-input `main` that calls no effect, so its output can depend only on
its input: a `clock_ns`, file, or argument builtin reaching it would itself
be the bug, and otherwise the cause is almost always a counter seeded from
something it should not be.

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
