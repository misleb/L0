# L0 specification changelog

Every change to the language is recorded here, with the reason it was made. The
spec itself ([L0.md](L0.md)) says only what L0 *is*; this file says why.

New entries go at the top.

---

## Reading and writing as a program runs

**L0 has effects.** Two builtins, `read_byte` and `write_byte` (section 6.2),
and a second form of `main`, `(def main () int ...)`, which reads nothing up
front and returns the exit status (section 9). This is the first change made
under "The route to memory management and I/O" below, and the one that ends
L0's purity. Sections 1, 8, and 10.3 change with it.

**The blocker.** Roadmap item 0006 could not write a program that asks for a
name and then greets it. The nearest L0 program printed its question after its
answer, measured with the answer sent at t+0 and end of input at t+3:

```
  t+ 0.00s  stdin  b'Ada\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'What is your name? Hello, Ada!\n'
```

Now `tests/io/prompt` holds the program 0006 said should have been possible,
and `prompt.sh` sends the answer only once it has read the question back. A
version that reads before it asks fails it after its 5-second watchdog, which
was checked. The same change removes two of 0006's memory costs, the whole
input held before `main` runs and the whole output held until it returns. A
streaming copy of 1, 10, and 100 MB peaks at 1.1 MB each time, where `main`
returning its input peaks at 18, 173, and 1704 MB.

**Why bytes, and not lines or strings.** The builtins are the smallest pair
the rest can be written from, so the runtime interface grows by two functions
and not by a family. `read_line`, `write_str`, and `write_line` are ordinary L0
in a new `lib/io.l0`, which `tools/l0` links beside `lib/prelude.l0` in the
prelude group, so a program may define its own. `read_byte` returns -1 at end
of input rather than a data type with an end case, so it needs no predeclared
type: a predeclared constructor would break every program that already used
its name, since section 7.1 does not group constructors. That problem is still
waiting for 0009, whose file operations can fail.

**Why `lib/io.l0` is not in the prelude.** The stage-0 interpreter runs
`lib/prelude.l0` and the compiler, both for the compiler's stage tests and for
`tools/l0check`, and stage 0 is frozen, so it will never know the new
builtins. The compiler's own source and the prelude therefore must not use
them.

**Why a second form of `main`, and not only the builtins.** The existing form
reads all of standard input before `main` runs, so `read_byte` inside it can
only ever see end of file. A program that streams has to be one the host does
not read for. Its result became the exit status because nothing else is
written on its behalf, and a program that streams needs a way to fail other
than a crash. That is a first installment of 0009's "failure". The runtime
calls every `main` the same way, so one with no parameters still compiles to
`@l0_f_main(i64)` and ignores the argument (section 10.2), and
`@l0_main_ret_kind` gains a kind 3.

The old form keeps working exactly as before, and can use the builtins too:
`read_byte` returns -1 from the start, and bytes written come before the
result.

**What the ordering costs, which section 8 had already priced.** Evaluation
order was specified left to right from v1 "so that even failure is
deterministic", and its paragraph said an effect would find the order already
pinned down. It did. What is lost is the implementation's freedom to reorder
or drop an evaluation that could have an effect, and section 8 now says an
evaluation may be moved or dropped only if it can neither do I/O nor fail. The
compiler never used that freedom. LLVM cannot use it either, since the
builtins are calls into the runtime.

**Output buffering is specified by what it must not hide.** An implementation
may hold output back, but only until a `read_byte` has to wait, or the program
ends, including by a runtime error. That is exactly what makes a prompt
appear, and it lets the runtime buffer 64 KB in each direction. A runtime
error now delivers what was written before it and then the diagnostic, rather
than producing no output at all, since output that had already reached a
terminal could not be taken back.

**Section 10.3's case for the arena is corrected.** It said never freeing was
correct because a program "runs once and exits", and named a program that runs
unbounded as the change that would break it. A program that streams is that
change. The paragraph now says what is true: never freeing is safe, memory is
total allocation, and a streaming program that allocates per line grows
without bound while one that does not stays constant. 0010 is the fix.

**Tests without an oracle.** Stage 0 cannot run any of this, so the new
`tests/io/` suite runs only under `tools/test.sh --compiled`, and its
expectations are written by hand rather than blessed. Checker errors for the
new builtins and the new `main` are in `tests/compiler/check_errors`, which
runs the compiler's checker under stage 0 and so still has both.

---

## Checking a fragment still checks its main

**A check that used to pass now fails.** With `#nomain`, a program `main` that
is present must still have section 9's signature. Section 9.1 says so, and a
wrong `main` is now reported at its declaration, with a file and line, rather
than at no position.

**The blocker.** Roadmap item 0006 wrote this, to show that command-line
arguments cannot be reached:

```
(def main ((args (list (list int))) (input (list int))) (list int)
  (head args))
```

`tools/l0check` printed `ok` for it. Checking passes `#nomain`, and a present
`main` was not examined at all, although 9.1 said `#nomain` "relaxes nothing
else". Only `tools/l0 build` rejected it, with no location:

```
error: main must take one parameter of type (list int)
```

The worker nearly recorded a blocked program as passing, because the one rule
it had been given was to trust `l0check`. A checker that says `ok` about a
program that cannot run is worse than one that says nothing.

**`tools/l0check` now uses the compiler's checker.** It used to run stage 0's,
which is frozen, so it could not have been fixed there. The compiler's checker
runs under the stage-0 interpreter, which executes the current
`compiler/*.l0` and so is never stale, and it takes about a tenth of a second
on a 30 KB file. This also had to happen before the next language item: once
L0 gains builtins stage 0 does not know, stage 0's checker would reject every
program that uses them. Stage 0's checker remains in use as the oracle in
`tools/test.sh`, which is its only job. Diagnostics now carry the compiler's
wording, which differs slightly from stage 0's.

When the compiler's own source starts using a feature stage 0 cannot run,
`l0check` will need a native compiler built from the current source instead.
It falls back to `build/l0c-native` already, but that one is only as current
as the last `tools/test.sh --compiled`.

**One more stale-compiler trap, found verifying this.** In a checkout,
`tools/l0` rebuilt `lib/l0c` from the seed only when it was missing, so after
a seed refresh `l0 check` and `l0 build` went on using the previous compiler,
and reported the old unlocated message. It now rebuilds when the seed or
`runtime/l0rt.ll` is newer than what it built. An installed prefix has no
seed beside it and is unaffected.

---

## The route to memory management and I/O

**No semantic change yet. L0 is exactly the language it was before this
entry.** What this records is a decision about what L0 becomes, made before
any of it is built, because it ends a property the spec has had since v1.

**The decision.** L0 gains memory management and I/O as safe facilities
implemented in the runtime, and I/O becomes effects in expression position,
ordered by section 8's existing left-to-right rule. L0 code does not get raw
memory. This ends L0's purity, deliberately. Section 8's guarantee that a
program which type checks cannot read uninitialized memory stays whole.

**The evidence.** Roadmap item 0002 tried to write the runtime in L0 and
found ten limits, every one of them a systems primitive: loads and stores at
an address, static storage, calls to C, symbol names, C types. Item 0006 then
wrote four ordinary programs, a line filter, a word counter, a prompt, and a
file copy. None of them needed any of those primitives. What they needed was
reclaimed memory, incremental standard input and output, arguments, files,
and a way to fail. The prompt and the file copy cannot be written at all
today, and the two that can are costly, measured:

- the line filter uses 53 bytes of memory per input byte, 16 GB for one pass
  over 300 MB
- the word counter, whose table never holds more than 14 entries, uses 208
  bytes per input byte
- a loop that never holds more than about 1 KB live reaches 9.8 GB after 10
  million iterations

**Why safe facilities rather than primitives.** L0 is written by agents, so
what counts is whether the checker catches their mistakes. An operation that
can fail can return a data type with a failure case, and exhaustive one-level
`match` then rejects a program that forgets the error path. Raw memory gives
the checker nothing: every value is an `i64` at run time, so a wrong pointer,
length, or errno passes. And freeing by hand cannot be made safe in L0 at all,
because lists share their tails invisibly.

**Reclamation will be reference counting.** It is complete for L0 without a
cycle collector: there is no mutation, evaluation is strict, and `let` cannot
define a recursive value (section 5.3), so an L0 heap can never contain a
cycle. It is also invisible to programs, so the whole differential suite
keeps judging it against stage 0.

**What this overrules.** "Output before input is an accepted blocker" below
preferred keeping `main` pure and re-running it on a longer transcript each
turn. That fixes prompting and nothing else: for the word counter it would
mean 2.8 million re-runs on 100 MB of input. Its blocker and measurement
stand; its preferred shape is rejected on this evidence.

**What was deferred, not rejected.** The systems primitives return to the
table if a program needs them, or if writing the runtime in L0 becomes a goal
in its own right. `roadmap/0002/` holds their list and first drafts.

**The order.** Checking enforces `main`'s signature first, a small fix 0006
found. Then streaming standard input and output, then arguments, files, and
failure, then reference counting. Streaming comes before reclamation because
it changes what can be written, not only what it costs, and 0006 measured
that neither bounds memory without the other.

---

## The runtime is LLVM IR, and stack exhaustion is checked rather than caught

**No change to what an L0 program means.** Every program produces the same
output, the same errors, and the same exit status as before. What changed is
what a compiled program is made of. Section 10.3 now says the runtime is LLVM
IR that calls libc, and adds one function to it, `@l0_stack_check`, which
every compiled function calls on entry.

**The blocker.** Every compiled program linked `runtime/l0core.c` and
`runtime/l0rt.c`, and "A new goal" below makes no C source in a compiled
program the first milestone. Roadmap item 0001 set out what the C did and
what each part needed from the operating system. Lists, data blocks, `div`,
`mod`, and error reporting need nothing but an allocator and `write`.
Allocation needs `malloc`, input and output need `read` and `write`, and the
entry point runs the program on a 512 MB thread so that deep recursion works.

**The replacement** is `runtime/l0rt.ll`, hand-written IR that calls 14 libc
functions and nothing else. It exports the same names the C did, so the
checked-in seed, which declares them, links against it unchanged. It carries
no target triple, and it is the same text on every host because it avoids
everything whose shape differs between operating systems:

- file descriptors rather than `FILE*`, whose symbol names differ
- no varargs, so no `printf`; decimal output is written out by hand
- `pthread_attr_t` as an opaque buffer larger than any platform's
- no signal handling at all

A prototype was measured before this change was made. On macOS arm64, and on
Linux aarch64 under Docker (Ubuntu 24.04, glibc, clang 18), with identical
results on both, it passed all 30 compiled tests against the interpreter's
expectations, and the compiler linked against it compiled itself
byte-identically.

**Why the stack is checked rather than caught.** The C runtime reported
exhaustion from a SIGSEGV/SIGBUS handler running on an alternate stack.
`struct sigaction`, the value of `SA_ONSTACK`, and the number of `SIGBUS` all
differ between macOS and Linux, and target-independent IR cannot express any of
them. So the thread records a limit when it starts, 256 KB above the bottom of
its stack, and each function compares its frame address against it. The cost
is one call per function entry. Measured against the C handler, exhaustion is
reported at exactly the same depth for every `L0_STACK_MB` tried, from 1 to
512.

The big stack stays, and is still sized by `L0_STACK_MB`. The compiler does
not need it: at `-O2`, LLVM turns its recursion into loops, and it compiles
itself on 1 MB. User programs do. Recursion that LLVM cannot rewrite, such as
rebuilding a list through `cons`, costs 32 bytes a frame on arm64, so the
default 8 MB stack fails on a 1 MB input that 512 MB handles. macOS could set
that size at link time, but Linux has no equivalent, so it is still a thread.

**A trap in the transition, and why this landed with a fresh seed.** The
compiler now emits the checks, but the seed predates them, so a compiler built
from it produces programs with no stack checks. Linked against the new
runtime, those programs crash with a bus error on deep recursion rather than
reporting it. Nothing in the test suite would have caught this, because
`--compiled` bootstraps from source first. It showed up only through
`l0 build`, which uses the installed compiler. So the seed was refreshed in the
same change, and there is no commit at which the installed toolchain loses the
error.

`tests/lang/err_stack` is new. Stack exhaustion had no test before.

**What stays C.** Only stage 0. `runtime/l0core.c` is now compiled for the
interpreter alone, and `tools/install.sh` compiles no C at all. `l0rt.c` is
linked by nothing; roadmap item 0004 deletes it and moves `l0core.c` under
`stage0/`.

---

## A new goal, and the agent that uses L0 is the one that changes it

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what L0 is for, and how it changes.

**The goal.** The README opened with a goal that has been met: "L0 does not
aim to be fast, general, or pleasant for humans. It aims to be expressive
enough to express its own compiler." "Purity is a property, not a premise"
below stopped the spec from treating self-compilation as the only goal, but
left the direction to whatever applications happened to request. The goal is
now stated in its own right, in three parts:

- **Compiled.** L0 compiles to native code through LLVM and is never
  interpreted at run time. That is the only sense in which it aims to be fast.
  Tail calls, inlining, and register allocation are left to LLVM, so L0 does
  not implement optimizations itself, and speed alone does not justify a change.
  Section 8 still leaves tail-call elimination unspecified; this is a statement
  of where the work lives, not a new guarantee.
- **General purpose.** L0 should express ordinary programs, not only its own
  compiler. Memory management and I/O come first, and the direction is for
  compiled programs to stop needing the C runtime in `runtime/`. That makes the
  cost notes in section 10.3 and in "Output before input" below live questions
  rather than hypothetical ones.

  "Without the C runtime" means no C source in a compiled program, not no
  libc. libc stays as the interface to the operating system, because on macOS
  it is the only supported one: Apple does not keep the raw system call ABI
  stable, which is why Go calls libSystem there rather than the kernel. A
  program that makes raw system calls would be Linux-only, and nothing in the
  goal is worth that.
- **Written for agents, not humans.** This is the one part of the old "does not
  aim" list that survives. L0 is read and written by an agent, so whether code
  comes out correct, and whether the checker catches it when it does not,
  outweighs brevity and familiarity.

Self-compilation stays the one property no change may cost.

**The process.** The request loop is retired: the `l0-limits` skill in
scaffolded projects, `l0 request` and `l0 submit`, the `requests/` inbox, and
triage here by the `l0-evolve` skill. It was too tedious to operate, and the
agents in those projects were too quick to work around a limitation instead of
reporting it.

The loop's own rules made that the expected outcome. The toolchain was
read-only, a workaround had to exist before a request could, and a cost that
was constant per use site was to be worked around "however tedious". Two
results of that are already on record. The compiler carries nine
near-identical result types for want of generics, which never qualified. And
the hell0 project shipped a greeting program that "does something adjacent to
what was asked, and its test suite passes" (see the entry below). A workaround
that ships absorbs exactly the pressure a language change needed.

Now the agent that writes L0 in this repository also changes it, and when L0
cannot express something the answer is to change L0. A change is still earned
by code — L0 in this repository that it makes possible, or makes harder to get
wrong — and the spec-first order, the two-step rule, and the frozen stage 0 are
unchanged. Those rules moved from the deleted `l0-evolve` skill into
`l0-bootstrap`, so that one skill covers every change that has to survive the
bootstrap.

`l0 init` still scaffolds a project with the spec, the examples, the prelude,
and the `l0-code` skill. The `AGENTS.md` it copies now tells an agent to name a
limitation plainly rather than ship a narrowed version of the task, since
nothing any longer carries a report back here.

**Earlier entries** cite `requests/`, `l0-limits`, and `l0-evolve`. They are
left as written; the files are in git history. Where a decision rested on the
loop's tests for change — constant per use site, three unrelated places, a
host-protocol question rather than a language one — it is to be re-argued
rather than inherited, as "Purity is a property, not a premise" already said of
purity.

**What did not change, deliberately.** The restrictions formerly under "What
makes a good feature" still stand: one-level `match` with no wildcard, no type
inference, `list` as the only parametric type, and no function values. Their
reason is restated for the new goal rather than dropped. They keep the checker
simple and every error local, which serves an agent writing L0 as much as it
served the bootstrap. Breaking one is allowed, and should buy something
substantial.

---

## Output before input is an accepted blocker

**No semantic change. L0 is exactly the language it was before this entry.**
Section 9 still has the host read standard input to end of file, then evaluate
`(main input)`, then write the result, and nothing in the grammar, the type
rules, the runtime, or the emitted IR has moved.

What this entry records is that the blocker behind a future change to that
ordering has been demonstrated, checked here, and accepted. It is written now
because the demonstration lives in a project that may change, and because the
same blocker arrived twice from the hell0 project, as requests `hell0-0001`
and `hell0-0003`, and was argued from scratch both times. The requests
themselves were retired with the request loop (see the entry above); what
mattered in them is quoted here.

**The blocker.** From `hell0-0003`, which states the task and the obstacle:

> The task: ask the user for their name, then greet the name they gave. One
> turn — write, then read what the writing caused.
>
> No L0 program can do this, and the obstacle is not syntax, so there is no
> code that fails to compile. What fails is the order.

The nearest expressible program returns the question and the answer together,
and so "prints `What is your name? Hell0, Ada!` — a question printed after its
own answer was consumed. The bytes are in the right order on screen and in the
wrong order in time."

**The measurement**, which is the part that would otherwise be unrecoverable.
`test/ordering/measure.sh` in that project supplies the answer immediately and
delays only end of file, so the two hypotheses predict outputs three seconds
apart. Reproduced here:

```
answer is readable at t+0; end of file comes at t+3s

  t+2.98s  got: Ada
  t+2.98s  |end

first output byte at t+2.98s.
```

> The answer was readable at t+0. No output byte appeared until t+2.98, when
> EOF arrived. [...] The program cannot emit a prompt while the user is still
> able to respond to it, on any input, because evaluation has not begun.

The script exits 0 while the limitation holds and nonzero if output ever
appears early, so it is also the check that would tell us this had been
fixed. `nm` on `lib/libl0rt.a` agrees from the implementation side:
`l0_read_stdin_list` and `l0_write_result` are the only symbols that touch the
byte channel, so there is one read and one write and no way to interleave them.

**What the workaround costs.** There is no workaround that performs the task:

> **The program cannot be written.** Not awkward — impossible. The requirement
> is that the program's output influence its own input. Section 9 orders all
> reading before all evaluation, so the two cannot both hold, and no amount of
> structure on the byte channel changes it: a format says what bytes mean, not
> whose turn it is.
>
> The cost is not line count. It is that the shipped program does something
> adjacent to what was asked, and its test suite passes, because the tests were
> written from the same contract.

What shipped is a program that greets a name on stdin and never asks for one —
"honest and it is not the task. An observer watching it run is never asked
anything." A bash wrapper that did the asking was tried first and rejected,
for a reason worth keeping: the turn lived in the shell, so the L0 half could
not decide whether to ask, or ask a second question whose wording depended on
the first answer.

> This generalises past greeting: a confirmation prompt, a menu, a retry on
> invalid input, and progress during a long run are all the same limitation.

**Why this is not the ordinary host-protocol case.** It was the one carve-out
in the `l0-limits` skill, and that carve-out existed because of this same
project's earlier skill note: structure says what bytes mean, it cannot say
whose turn it is. The precedent for reaching for a format instead of a feature
is strong — see "Input bundle" and "Compiler output protocol" below, three
problems in a row that looked like they needed a primitive and needed none —
but all of that evidence comes from the compiler, which is a batch program that
never wanted a turn. It is evidence about content and silent about ordering.

**What is accepted, and what is not.** The blocker, and the general shape of
the fix: `main` stays a pure function from bytes to bytes and is re-run on a
longer prefix of the transcript each turn, recomputing rather than resuming, so
nothing captures a continuation and determinism and replay are preserved.

Not accepted, twice now, is putting the turn directive in the type system — a
predeclared `Turn`, or the `Step`/`Done`/`More` of `hell0-0003`. Section 7.1
does not group type and constructor names, and "Why types and constructors are
not grouped" below records that as structural rather than an oversight, so a
predeclared constructor breaks every program that already used the name, with
no shadowing escape. The directive belongs on the byte channel, where the
compiler already puts `O` and `E`, which costs no name, no second entry point,
and no checker case.

**What it will cost when it is made**, so that the price is on record:

- **Sections 1 and 9.** The purity boundary moves. Individual `main` calls stay
  pure and the language still has no I/O primitive, so section 8 is untouched
  and evaluation order stays unobservable. This is why a host loop is much
  cheaper than an effect in expression position.
- **Section 10.3, which asks to be costed directly.** `hell0-0003` is the first
  request to do so, and its answer is accepted: re-entry is bounded by the turns
  the program asks for, the process still runs once and exits, so the bump arena
  stays correct, and a program demanding unboundedly many turns exhausts the
  heap — already a runtime error under section 8, already reachable through
  unbounded recursion. What is given up is the guarantee that total allocation
  is bounded by a single evaluation. A fresh process per turn avoids even that,
  which is why the out-of-process loop is the cheaper first step.

Streaming `main`'s result as it is produced was considered and is a different
change. It would fix progress reporting and not prompting, since stdin is still
consumed before `main` is called, and doing it properly needs non-strict
evaluation, which section 8's strictness rules out as load-bearing.

*Qualified later, by "A new goal": I/O is now a goal in its own right rather
than something an application has to prove it needs. The blocker and the
measurement above stand. The preference for keeping `main` pure and moving
the turn into a host loop was argued under the old goal, when the aim was to
change as little as possible, and is one candidate to re-argue rather than the
settled shape.*

---

## Purity is a property, not a premise; self-compilation is not the only goal

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what the spec claims about its own
permanence, which had started to govern decisions it was never meant to govern.

**The blocker.** Two sentences in the spec's opening — "L0's single goal is to
be able to compile itself" and "Everything in this document exists because it
serves that goal" — were written before self-hosting was reached. They are a
true account of how v1 came to be and a false account of what governs L0 now.
The `l0-evolve` skill already says the opposite: "Self compilation supplied
that pressure until it was reached; applications written in L0 supply it now."
A spec and a skill that disagree about what justifies a change is not a
cosmetic problem, because the spec wins, and the spec's version rejects on
sight any request arising from an application rather than from the compiler.

That is not hypothetical. `requests/hell0-0001-interactive-input.md` asks for
interactive prompting, which self-compilation will never need: the compiler is
a batch program. Under the old opening the request is refused without reading
the evidence. Under the new one it is judged on whether the blocker is real.
The ambiguity was deciding requests by itself, which is the one thing an
ambiguity must not be allowed to do.

**Smallness.** No rule anywhere required L0 to stay small, and none does now.
What exists is a bar for change — it grows when real code cannot be written
without the addition — which is a justification requirement, not a size cap.
The opening now says smallness is a description rather than a vow, so that the
bar is argued about on its own terms.

**Purity.** Three rules leaned on purity, two of them silently, and the fix is
to name the dependency at each site rather than to weaken any of them:

- Section 8 derived the unobservability of evaluation order from purity. The
  left-to-right rule itself never depended on purity and is unchanged; what
  purity buys is an implementation's freedom to reorder pure arguments. That
  is now stated as the thing a change would cost.
- Section 10.3 said the bump arena is correct "because an L0 program is a
  single pure evaluation that runs once and exits". Purity was doing no work
  in that sentence. The arena is correct because the run is *bounded*, and an
  impure L0 that still ran once and exited would not disturb it. Section 10.3
  now says so, and names re-entry and unbounded running as the changes that
  would put a collector back on the table. This is a real finding rather than
  a rewording: it means a resumable entry point is an allocator question,
  which nothing in the spec previously said.
- Section 1 asserted purity flatly. It now adds that the impurity lives in the
  host by v1's choice of boundary, and points at the two sections above.

The claim that purity was merely the cheapest route to bootstrapping does not
survive the record, and is not the reason for this entry. Purity was a
deliberate placement — see "An entry point and a host contract" below: "this
adds no I/O to L0 itself: `main` is still a pure function, and the impurity
lives entirely in the host." It remains load-bearing. The point of naming what
rests on it is that a future proposal can price the change instead of
discovering the dependencies one broken derivation at a time.

**What did not change, deliberately.** The language must still be able to
compile itself. That is now stated as the one property no change may cost,
which is a stronger and narrower claim than "everything serves that goal": it
forbids a change that breaks self-hosting, and permits one that merely fails to
advance it. Every restriction in "What makes a good feature" also still stands;
this entry loosens the stated *purpose* of the language, not the bar any
individual change has to clear.

A program may now define a function the prelude already defines. The program's
definition wins throughout the program; the prelude goes on calling its own.
Spec section 7.1 states the rule, 9.1 states how a compiler is told where the
boundary is, and 10.2 gives the prelude its own symbol prefix.

**The blocker.** Before this, the prelude occupied the same flat namespace as
the program, so a project that had written its own `length` could not compile
at all:

```
clash.l0:1:1: error: function length is already defined
```

That makes every addition to `lib/prelude.l0` a breaking change for programs
that already exist, and the hazard grows with the prelude: the more it holds,
the likelier any given project has already used one of the names. This is the
"cost grows with the program" case in the `l0-limits` skill, and it is the one
cost of prelude growth that the emitted-linkage change immediately before this
did not touch. Compiled size was the other, and is now nothing.

The workaround was `l0 build --no-prelude`, which trades one name for the
whole library, and which the shipped `AGENTS.md` did not even mention.

**Why two groups and not a module system.** A general module system was
considered and rejected. Imports would mean path resolution inside a compiler
that is by definition a pure function from bytes to bytes, so the work lands in
the driver either way; what it would buy is separate compilation, which this
project does not want, because whole-program checking is exactly what lets the
checker do without inference. Measured by the `l0-limits` test, needing to name
every file on one command line is a cost that is constant per use site. Name
isolation was the only part that was not.

So the addition is deliberately not general: there are exactly two groups, not
n, nothing in a source file can say what it needs or exports, and the grouping
comes from the input protocol rather than from L0 syntax.

*Qualified later, by "Purity is a property, not a premise": "by definition a
pure function from bytes to bytes" describes v1, not a fixed truth. The
argument above is left as it was made, since it is the reasoning that was
actually used. If purity is ever revisited, this rejection is one of the
things that has to be re-argued rather than inherited.*

**Why the program's definition does not simply replace the prelude's.** The
cheaper rule — one namespace, last definition wins — was rejected because it
is monkey-patching. A program defining its own `list_eq` would silently change
what the prelude's `any_eq` and `index_of` do, and nothing would report it.
Two scopes cost a symbol prefix and catch that at the point of definition
instead, which is the trade this project has taken every other time it came
up.

**The compiler itself is still compiled as one group.** `tools/l0` marks the
prelude for a user's program; `tools/l0c`, which builds this repository and
runs its tests, does not, because when the compiler is built `lib/prelude.l0`
genuinely is part of the program rather than a library beneath it. So
`bootstrap/stage2.ll` carries `@l0_f_length` and not `@l0_p_length`, and the
grouping is exercised by `tests/compiler/prelude_scope` and
`tests/compiler/bundle_prelude` rather than by the bootstrap. This also kept
the two steps apart: the compiler learned to read `#prelude` and the seed was
refreshed before any driver started writing it, so no fresh clone ever sees a
header its only compiler cannot parse.

**Why types and constructors are not grouped.** A `match` arm names a
constructor without naming its type, so constructor resolution has to be
global for one-level patterns to resolve at all, and `ty_eq` compares types by
name, so two same-named types could not be told apart. Grouping function names
needs neither. The restriction is recorded in 7.1 so that a later attempt to
group them starts from the reason rather than from the omission.

---

## Emitted linkage — resolved

Every function except `main` is now emitted as `define internal`, so the
prelude no longer costs anything in a program that does not use it.

No language change. The spec does not describe linkage, and it still does not:
this is a fact about the emitter, recorded because the reasoning behind it is
what makes the next question answerable.

The old emitter gave every function external linkage. Nothing can remove an
externally visible symbol, so a hello-world compiled with the prelude carried
all 30 prelude functions into its object file at 10704 bytes, of which it
called none. With internal linkage on everything but `main`, LLVM's `-O2`
deletes the unreachable ones and the same object is 1168 bytes.

`main` stays external because [../runtime/l0rt.c](../runtime/l0rt.c) calls
`l0_f_main` by name, and `@l0_main_ret_kind` stays a plain global for the same
reason. Those two symbols are the entire interface a compiled program exposes;
a program is otherwise a closed module, which is what makes internal linkage
correct rather than merely convenient.

This was prompted by the observation that `lib/prelude.l0` will keep growing
and that every program pays for all of it. Half of that was true and is now
false. What remains true is that the prelude occupies the same flat namespace
as the program, so a project that defines its own `length` cannot compile:

```
clash.l0:1:1: error: function length is already defined
```

That is the cost that actually grows with the prelude, and it is a language
question rather than an emitter one. Recorded here as open, deliberately
separate from this change. Compile time is not part of the picture: the whole
prelude adds about 2 ms to a hello-world.

The seed was refreshed in the same change, since the emitter's output shape
changed. The fixpoint held first: a seed built before this change compiles the
new compiler to `stage1.ll` with the old linkage, and that compiler then
reaches `stage2.ll == stage3.ll` with the new.

---

## Self-hosting reached

`compiler/*.l0` compiles itself to a byte-identical fixpoint, and
`bootstrap/stage2.ll` is checked in as the bootstrap seed. Verified by
removing `stage0/` entirely and rebuilding the compiler from the seed alone.

No language change was needed to get here. L0 v1 as specified was sufficient
to express its own compiler, which was the entire point of the design.

Two things are worth recording because they were predicted and held:

**The monomorphism pressure never became a blocker.** The compiler carries
nine near-identical "value or error" result types that a parametric data type
would collapse into one. That was annoying and never worse than annoying, so
parametric data types remain unjustified. The blocker that would justify them
has still not appeared.

**Nothing needed I/O.** The compiler is a pure `(list int) -> (list int)`
function, and everything that looked like it wanted a primitive turned out to
be a protocol on the single channel instead.

---

## Input bundle — resolved

Diagnostics now report `file:line:column` rather than a line number in the
concatenated stream, and again no language change was needed.

Input may optionally begin with a table of byte offsets and paths:

```
#l0bundle
0 util.l0
41 main.l0
#source
<the concatenated file contents>
```

The compiler maps a diagnostic's byte offset back to the file containing it
and measures line and column from that file's start.
[../tools/l0c](../tools/l0c) builds the bundle. Input that does not begin with
`#l0bundle` is treated as a single unnamed source, so piping a bare file still
works and the bootstrap is unaffected.

This was recorded as an open question and became worth fixing the moment the
compiler was pointed at a real multi-file project: an error on line 2 of the
second file was reported as line 3, which points at nothing and sends the
reader to the wrong place entirely.

That makes three problems in a row that looked like they wanted an I/O
primitive and were solved instead by putting a little structure on the single
byte channel. The pattern is worth trying before reaching for a language
feature.

---

## Compiler output protocol — resolved

The question of how a compiled program distinguishes "here is my output" from
"I failed, and here is why" is settled, and needed no language change.

`main` returns a **tagged stream**: `O` and a newline followed by LLVM IR, or
`E` and a newline followed by diagnostics, one per line.
[tools/l0c](../tools/l0c) strips the tag, routes the remainder to stdout or
stderr, and sets the exit status, so callers see an ordinary unix compiler.

A printable tag was chosen over a leading zero byte so that raw compiler
output stays readable under `head` while debugging.

This confirms the reasoning recorded when the question was opened: a pure
`bytes -> bytes` function plus a slightly richer host protocol goes much
further than it appears, and the things that look like they need I/O
primitives usually do not.

---

## v1 — initial spec, superseding the seed

[L0.md](L0.md) replaces [../seeds/spec.md](../seeds/spec.md) as the single source
of truth. The seed is kept unchanged for history.

### Added

**String literals.** `"add i64 "` denotes a `(list int)` of byte values.
*Reason:* the compiler's entire output is text. Without literals, every emitted
fragment would be a hand-written `cons` chain, which is unreadable and
unmaintainable at the scale of a code generator.

**Parametric lists, `(list T)`.** The seed had a single `list` type meaning
"sequence of int". *Reason:* a compiler needs a list of tokens and a list of
declarations, not just a list of integers. This is the one generic type
constructor in L0; user data types are monomorphic, which avoids needing
unification or type inference anywhere in the checker.

**`data` declarations and `match`.** Tagged unions of fixed-arity constructors,
with one-level-deep exhaustive pattern matching. *Reason:* an abstract syntax
tree is a sum type. Without one, the AST would have to be encoded into a flat
`(list int)` with a hand-rolled allocator, making every access O(n).

Patterns are deliberately restricted to one level with no wildcard arm, so
exhaustiveness checking is a matter of counting constructors and `match` codegen
is a jump table. Nested patterns would require a pattern-match compilation
algorithm in the self-hosted compiler, which is a large amount of work for
convenience alone.

**An entry point and a host contract.** A program declares `main`, the host
supplies stdin as a byte list and writes the result to stdout. *Reason:* the
seed spec described a language in which nothing could be run or tested. Note
that this adds no I/O to L0 itself: `main` is still a pure function, and the
impurity lives entirely in the host.

**A compilation target (section 10).** Value representation, generated symbol
names, and the runtime interface. *Reason:* the L0 compiler must emit exactly
this, so it is part of the language's contract rather than an implementation
detail. Pinning it down also allows the "every value is an `i64`" simplification
to be relied upon rather than rediscovered.

### Changed

**`int` is 64-bit, not arbitrary precision.** *Reason:* the seed promised
arbitrary precision, which means shipping a bignum library in the runtime before
a single L0 program can run. GMP is not installed, and a self-hosting compiler
never needs a value above 2^63. Keeping the spec honest matters more than
keeping it ambitious, because the spec is an agent's only source of truth and an
aspirational claim here would become a silent correctness bug.

**`nil` is an expression form, not a builtin.** It is now written `(nil int)`
with an explicit element type. *Reason:* with parametric lists, bare `(nil)` has
no determinable type. The alternative was bidirectional type checking to
propagate an expected type inward, which is real machinery and interacts badly
with recursion and `if` branches. An explicit type argument keeps the checker
completely inference-free.

**Names are split into lower and upper by first character.** Functions,
parameters, and bindings are `[a-z_]...`; types and constructors are `[A-Z]...`.
*Reason:* it lets a reader distinguish a constructor from a variable with no
context and no symbol table, which keeps both the parser and the eventual
self-hosted checker simple.

**`int`, `bool`, and `list` joined the reserved words**, alongside the seed's
`def`, `if`, `let`, `true`, `false`, plus the new `data`, `match`, and `nil`.

### Resolved ambiguities

The seed spec did not settle these. Each was decided to keep the language
deterministic and the checker simple; any of them can be revisited.

**Argument evaluation order** is left to right. *Why it matters:* L0 is pure, so
order is unobservable except for which runtime error fires first. Specifying it
makes failure deterministic, which in turn makes error tests reproducible.
*(Still the rule. See "Purity is a property, not a premise": the ordering does
not depend on purity, so a change to purity would cost the unobservability and
leave the left-to-right rule standing.)*

**`mod` takes the sign of the dividend.** The seed said division truncates
toward zero but did not say what `mod` does with negatives. Truncated division
implies the remainder follows the dividend, so `(mod -7 2)` is `-1`. This is what
LLVM's `srem` and C both do, so it is free to implement.

**Overflow wraps** rather than trapping, including the three cases that would
otherwise be undefined: `(div INT_MIN -1)` is `INT_MIN`, `(mod INT_MIN -1)` is
`0`, and `(neg INT_MIN)` is `INT_MIN`. *Why:* wrapping maps directly onto LLVM
arithmetic at zero cost. The three special cases are called out because LLVM's
`sdiv` and `srem` treat them as undefined behavior, so the runtime must handle
them explicitly to keep the language total.

**`let` shadowing is allowed.** An inner binding shadows a parameter or an
enclosing binding of the same name. *Why:* forbidding it forces gratuitously
unique names in deeply nested code, and accumulator-passing style produces a lot
of nesting.

**Locals and functions occupy separate namespaces** (section 7). A lower name in
call position is always a builtin or a `def`; a lower name anywhere else is
always a local. *Why:* L0 has no first-class functions, so a local can never be
called and a function name can never be a value. Making the rule syntactic
removes an entire class of resolution ambiguity, and it means a parameter named
`length` does not shadow a function named `length`.

**Shadowing a builtin is legal but the builtin always wins** in call position,
which makes a `def` named `add` uncallable. Rejecting it outright would be
defensible; allowing it keeps the resolution rule uniform, and it is a lint
concern rather than a correctness one.

**`eq` remains int-only.** Comparing lists or data values is a function written
in L0. *Why:* structural equality on arbitrary types is a polymorphic builtin
whose implementation needs runtime type information, which the "every value is
an `i64`" representation deliberately discards.

**Duplicate declarations are errors**, enumerated in section 4: duplicate
functions, duplicate types, duplicate constructors even across different types,
and duplicate parameter names. Constructors share one global namespace because
`match` arms name a constructor without naming its type, so the constructor has
to determine the type on its own.

**A `data` declaration needs at least one constructor.** An empty one would
declare an uninhabited type, which is useless here and would make `match`
exhaustiveness vacuous.

**`match` has no wildcard and no default arm**, and every constructor must appear
exactly once. *Why:* adding a constructor to a `data` type then becomes a compile
error at every site that must handle it, which is the property that makes
evolving the compiler's own AST safe.

**Recursive and mutually recursive data types are allowed**, since trees are the
point.

**String literal details.** The escape set is exactly `\n \t \r \\ \" \xHH`; any
other escape is an error. A raw newline inside a string literal is an error, so
that an unterminated string is caught on its own line instead of swallowing the
rest of the file. Literals produce unsigned bytes, never negative elements.

**Integer literal details.** A literal must fit in 64 bits, and a `-` is part of
a literal only when immediately followed by a digit. `- 3` is an error rather
than a subtraction, because `-` is not a name in L0.

**Runtime errors exit with status 70** and write one line to stderr, producing no
stdout. 70 is `EX_SOFTWARE` from `sysexits.h`, chosen so it cannot be confused
with a type error (status 1) or with a signal.

**Stack and heap exhaustion are reported as runtime errors** in the same form.
They are the only two failures a well-typed program can suffer that are not in
the list of four, and since L0 has no loops and no tail-call guarantee, deep
recursion is a realistic outcome rather than a pathological one.

**Output bytes are reduced modulo 256.** `main` returns a `(list int)` whose
elements are full 64-bit integers, so out-of-range elements need a defined
behavior. Truncating is quieter than erroring and matches how the bytes were
produced on the way in.

**Multiple source files are concatenated.** Declaration order is already
irrelevant, so file splitting is an editing convenience with no semantics. This
avoids designing a module system, which the bootstrap goal does not require.
