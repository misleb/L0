# Ordinary programs, and where L0 stops

Four everyday programs, written against `spec/L0.md` as of commit `9c1f0ba`
to find what general-purpose L0 needs. The rule was to stop at each limit
rather than write around it. Roadmap item 0006.

| Program | Status | What runs | What it does not do |
| --- | --- | --- | --- |
| [linefilter](linefilter/) | partly written | keeps lines containing `ERROR`, matching `grep`, up to 300 MB | memory proportional to one line (it uses 53 bytes per input byte); output before end of input; substring from argv |
| [counter](counter/) | partly written | running per-word counts reported per line, matching `awk`, up to 100 MB | memory proportional to its state (it uses 200 bytes per input byte for a 1 KB table); a report per line as the line arrives |
| [prompt](prompt/) | blocked | nothing; the question can only appear after end of input | everything |
| [filecopy](filecopy/) | blocked | nothing; no arguments, no files, no failure exit | everything |

The limits, each with its smallest program, are in [limits/](limits/). The
code that should have been possible is in [hypothetical/](hypothetical/).

## Reproducing

All scripts work from any directory and build with `tools/l0`. Generated
inputs go to a temporary directory and are deleted afterward.

| Script | Produces |
| --- | --- |
| `check.sh` | `check.txt`: `tools/l0check` on every `.l0` here, plus `l0 build` on limit 05 |
| `test.sh` | linefilter and counter against the committed expected outputs |
| `limits/measure.sh` | memory tables for limits 01–03 |
| `linefilter/measure.sh [MB ...]`, `counter/measure.sh [MB ...]` | memory tables, each checked against `grep` / `awk` |
| `linefilter/timing.sh`, `counter/timing.sh`, `prompt/measure.sh` | output-versus-input timelines |
| `counter/tailcalls.sh` | the counter at -O0/-O1/-O2 |
| `common/genlines.sh MB [noid]` | the deterministic input generator |

## What the numbers say

Memory in L0 today is the sum of three separate costs, and each has a limit
program that isolates it:

| Cost | Bytes | Limit |
| --- | --- | --- |
| stdin, built as a list before `main` | 17 per input byte | 01 |
| every cell ever allocated, live or not | 16 per cell | 02 |
| the output, built as a list before writing | 16 per output byte, 32 with `rev` | 03 |

For the line filter these add up to 53.5 bytes per input byte, and for the
counter to about 208. Fixing any one cost leaves the others. A collector
alone would take the counter from about 208 to about 86 bytes per input byte
(8.6 GB for a 100 MB input), since the input and output lists are live
data. Streaming I/O alone would leave the ~120 bytes of never-freed garbage.

## Things in `spec/L0.md` that are ambiguous or wrong

1. **Checking does not enforce `main`'s signature, and the spec does not say
   whether it should.** Section 9 says `main` must take one `(list int)`.
   Section 9.1 says `#nomain` means "do not require a `main`" and "relaxes
   nothing else", but not whether a `main` that is present with the wrong
   signature is still an error. `tools/l0check` (stage 0's `check`) and
   `tools/l0 check` (which sends `#nomain`) both print `ok` for
   `limits/05-no-command-line.l0`. `tools/l0 build` rejects it, and its
   message has no file or line, where `build/l0i run` gives
   `05-no-command-line.l0:14:6`. The repository's rule is "never claim L0
   code works without running `tools/l0check`", so an `ok` from l0check for
   a program that cannot be built is a trap. I nearly recorded limit 05 as
   "checks" before building it.

2. **Section 1 undercounts what rests on writing output after `main`
   returns.** Section 1 says moving the purity boundary changes "this section
   and the two rules that lean on it, in sections 8 and 10.3". A third rule
   leans on it without being named. Section 8 says a runtime error "produces
   no standard output". That rule holds only because nothing is written until
   `main` has returned; the runtime says so ("Standard output is written only
   after main returns, so a runtime error leaves it empty"). Any streaming
   output, which the filter, the counter, and the prompt all need, has to
   revise it.

3. **Section 10.3's case for the arena is incomplete.** It says the arena is
   correct because the run is bounded, and that only unbounded running or
   re-entry would break it. The measurements show one bounded run is not
   enough. Limit 02 uses 9.8 GB to hold 1 KB of live data. The line filter
   needs 16 GB for one pass over 300 MB. The arena is correct only when total
   allocation, not the lifetime of the run, fits in memory. For ordinary
   input sizes that fails in a single run.

4. **Tail calls decide whether a loop can run long, and the spec leaves them
   unspecified.** Section 8 says it does not specify whether non-terminating
   recursion runs forever or dies. For a long-running loop, that is not an
   edge case; it is the whole question. The counter completes a 10 MB input
   at -O1 and -O2 and dies of stack exhaustion at -O0 (`counter/tailcalls.sh`).
   The spec also never defines tail position. The counter recurses from
   inside `match` arms, and whether those calls count is left to LLVM.

## What I think the smallest additions are

This section is my opinion, based on the evidence above.

**The set.** These four programs need six things. None of them is new
syntax.

1. **Reclamation of unreachable memory.** It needs no syntax;
   `hypothetical/02`'s `bump` is the same text as `counter.l0`'s. L0 values
   are immutable, and `let` cannot bind a recursive value, so every value is
   built from values that already exist. The heap therefore cannot contain a
   cycle, and reference counting is complete, with no cycle collector.
2. **Reading stdin incrementally**, for example `(read_line)`, which returns
   the line with its `\n` and is empty only at end of input. That encoding
   separates an empty line from end of input without predeclaring a type.
3. **Writing stdout incrementally**, for example `(write_stdout bytes)`,
   flushed before any read, so that a question is visible before its answer
   is read.
4. **argv**, as a `main` that takes `(list (list int))`.
5. **Files**: open, read a chunk, write, close, with an opaque handle type.
6. **stderr and an exit status**, for example with `main` returning the
   status in the argv form.

Items 2 and 3 are effects in expression position, sequenced by `let`.
Section 8 already fixes left-to-right order, so nothing new has to be
decided there. What is given up is the unobservability of evaluation order,
which section 8 already names as the cost.

The accepted direction in the changelog, re-running a pure `main` on a
longer transcript each turn, fixes the prompt and none of the others. The
counter would take one turn per line: 2.8 million re-runs over a growing
prefix for the 100 MB input. It also does not address memory, argv, or
files.

**High-level facilities or low-level primitives?** For these programs,
high-level facilities, clearly. Every gap I hit is naturally a high-level
operation: a line, a write, a file, an argument, an exit status. Raw
loads, stores, and C calls could implement all of them, but an ordinary
program written against `read(fd, buf, n)` has to allocate and free a
buffer, turn a `(list int)` path into a NUL-terminated string, check for
`-1` and errno, and loop over short writes (as `write_all` in
`runtime/l0rt.ll` does). Every value is an `i64` (section 10.1), so the
checker cannot tell a pointer from an int from a list, and none of those
mistakes would be caught. It would also void section 8's promise that a
checked program cannot read uninitialized memory.

The cleanest reclamation choice points the same way. Freeing by hand is
unsafe in L0 because sharing is everywhere and invisible. `bump` returns
`(tail t)`, which is shared with the previous table, and `push` shares its
accumulator. Nothing in the types marks what is shared, so no checker could
catch a double free.

If low-level primitives are wanted for writing the runtime in L0 (roadmap
0002), section 7.1 already separates a prelude group from a program group.
Allowing the primitives only in the prelude would let the high-level
facilities be written in L0 without handing raw memory to every program.

**What the checker would catch.** All my L0 checked on the first try. The
mistakes I made or nearly made were ones no type checker catches today:

- **Dropping the last line when input has no final newline.** Both the filter
  and the counter needed explicit handling, the counter through its `mid`
  flag. A `read_line` with the contract above handles it once, in the runtime.
- **Measuring the wrong thing.** The first generator gave every line a unique
  id, which would have grown the counter's "small" table without limit.
  Nothing in L0 makes allocation visible.
- **Underestimating allocation by half.** I estimated about 100 bytes per
  input byte for the counter; it is 208. `rev`, `digits`, and `bump`'s copy
  all allocate, and nothing in the source says so.
- **Trusting `l0check` on limit 05** (spec item 1 above).

Of the proposed facilities, the one that gives the existing checker real
work is open returning a data type (`Opened File | OpenFailed reason`).
One-level, exhaustive, wildcard-free `match` then rejects a filecopy that
forgets the failure case. With a low-level `open` returning `-1`, an
unchecked failure is invisible. Neither design catches use after `close` or
a forgotten `close`; that would need linear types, which these programs do
not justify. Two costs are on record for this design. A predeclared `File`
and `Opened` collide with programs' own names, because type and constructor
names are not grouped (section 7.1). And effects make strict `and`/`or` a
new trap: `(and (not done) (write_stdout x))` writes even when `done` is
true, and the checker cannot tell.

**Not needed, but it multiplies every number here:** `(list int)` costs
16 bytes per byte. With streaming and reclamation, that cost applies only to
one line or one chunk, so none of these four programs needs a compact byte
type. Without them, it is the factor behind every table above.
