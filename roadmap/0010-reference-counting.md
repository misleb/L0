# 0010: Reclaim memory by reference counting

Kind: language
Status: done
Needs: 0009

## Why

From [0006](0006-ordinary-programs.md), `0006/limits/02-no-reclamation.l0`: a
loop that never holds more than 64 list cells at once, about 1 KB, reaches
9.8 GB after 10 million iterations, at 16 bytes per cell ever created. With
streaming I/O in place, 0006 estimates the word counter would still produce
about 120 bytes of garbage per input byte, never freed.

Reference counting is complete for L0, with no cycle collector, because an L0
heap cannot contain a cycle: there is no mutation, evaluation is strict, and
`let` cannot define a recursive value (section 5.3). See
[0005](0005-memory-and-io-route.md).

## Open questions for this item

- How the emitter keeps the types it now discards, and how a heap block says
  which of its words are pointers, since a cons cell's head may be an `int`.
- Where increments and decrements go, and whether updating in place when a
  count is one comes in the same change or later.
- How to split it into bootstrapped changes. It is invisible to programs, so
  the whole differential suite keeps judging it against stage 0.
- Section 10.3's case for the arena is corrected here: what must fit in
  memory is total allocation, not the length of the run.

## Done when

- the checklist in the `l0-bootstrap` skill
- `0006/limits/02-no-reclamation.l0` runs in memory that does not grow with
  its iteration count
- the compiler compiling itself peaks below 104.8 MB, its peak on the
  107 KB source before this item began; the 74.5 MB first recorded here was
  on a smaller source

## Log

- 2026-09-23: opened from 0005's recommendation.
- 2026-09-24: **design pass**, from reading `emit.l0` and the runtime.

  *Ownership, without liveness analysis.* Every pointer-typed value an
  expression produces is an owned reference, and whoever receives it
  consumes it: an argument to a user function (parameters are owned by the
  callee), a field stored by `cons` or a constructor, a `let` binding, or the
  function's result. A use of a pointer-typed variable increments it, since
  the variable keeps its own reference, and the variable's reference is
  released when its scope ends. That needs no analysis of later uses, only
  the types of variables. It releases a value no later than the end of the
  scope that binds it, not at its last use; tighter release can come later
  if a measurement asks for it.

  *Releases happen before a tail call.* `if` and `match` join their branches
  through a stack slot, so releasing at the end of a function would put a
  decrement after every recursive call and turn loops LLVM now makes into
  jumps back into real recursion, which would exhaust the stack on long
  inputs. So the emitter tracks tail position and the variables in scope:
  in tail position, a branch evaluates its value or its call's arguments,
  then releases every variable in scope, then makes the call. This is also
  what frees a list as a loop walks it: `rev_onto` drops its cell before
  recursing.

  *Borrowing builtins.* `head`, `tail`, `is_empty`, a `match` reading fields,
  and the I/O builtins taking a path all read their argument without
  consuming it. The emitter increments what they return when its static type
  is a pointer, then releases the argument. The runtime needs no new
  consuming versions of them.

  *Types in the emitter.* The emitter discards types today; an operand is
  bare text. `EmitVal` gains the value's type, computed bottom-up exactly as
  the checker computes it, so every expression's type is known when emitted
  with no second pass and nothing quadratic. Bindings in `Env` gain their
  type.

  *The runtime.* One header word before every block, so section 10.1's
  offsets do not move: a 24-bit count, the block's size in words, and a
  32-bit mask of which words are pointers. A cons cell's head may be an
  `int` or a pointer, which only the static type knows, so allocation takes
  the mask: new `l0_new_cons(h, t, headptr)` and
  `l0_new_data(tag, nfields, mask)`, plus `l0_inc` and `l0_dec`. The mask
  caps a constructor at 31 fields; the widest in the repository has 5, and
  section 4 gains the error. A count that reaches its maximum sticks there
  and the block is never freed, which is safe. Freeing walks the pointer
  words with an explicit worklist, not recursion, since freeing a long list
  recursively would exhaust the stack. Freed blocks go onto free lists by
  size, which allocation takes from before the arena.

  *The seed.* The old `l0_cons` and `l0_data_new` stay, per the append-only
  rule, and make blocks with a count already at the maximum, so programs the
  old seed compiled are never freed and never corrupted. Lists the runtime
  builds, input and arguments, are counted; an old-style program never
  releases them, which is today's behavior.

  *How it will be verified.* `L0_RC_CHECK=1` makes the runtime count live
  counted blocks and, at a normal exit, after releasing `main`'s result,
  report any left over, and fill freed blocks with a poison value so a use
  after free crashes or shows. `tools/test.sh --compiled` will set it for
  every run, so any leak or use after free in any compiled test is a
  failure, judged against stage 0's expectations as always. The targets are
  this item's: `0006/limits/02-no-reclamation.l0` in memory that does not
  grow, and the compiler compiling itself below 74.5 MB.

  *Two bootstrapped changes.*
  1. Types through the emitter, the new allocation calls with their masks,
     the header, and the free-list allocator, with nothing freed yet.
     Behavior is unchanged and memory grows by one word per block. The
     emitter refactor is most of the risk, and lands here, where the
     differential suite can check it before any counting exists.
  2. Increments and releases, tail-position releases, `L0_RC_CHECK` in the
     suite, the spec's memory guarantee, and the measurements.
  Neither needs the two-step rule, since the compiler's own source uses
  nothing new; each refreshes the seed in its own commit.

  *What 0011 needed to know.* Releases before a tail call keep tail calls
  where they are. Whether L0 should guarantee them is still 0011's question.
- 2026-09-24: **change 1 done**; changelog "Blocks describe their own
  layout". The emitter carries types; allocation goes through
  `l0_new_cons` and `l0_new_data` with masks (checked on lists of ints, lists
  of lists, and data with list and data fields); every block has a header;
  the free-list allocator is in place; constructors are limited to 31
  fields, with a failing case in `check_errors`. Both suites pass (56 and
  63), the fixpoint holds, and the seed is refreshed. Measured: the compiler
  on today's 107 KB source went from 104.8 MB to 179 MB resident, more than
  the header explains, because the emitter's new bookkeeping and longer
  output are garbage nothing frees yet. The item's memory target is for
  after change 2, against the 104.8 MB baseline on this source; the old
  74.5 MB figure was on a smaller source.
- 2026-09-24: **change 2 done, and the item**; changelog "Memory is
  reclaimed by reference counting". The bootstrap reached a byte-identical
  fixpoint on the first try with counting emitted. Against the Done when:
  - `0006/limits/02-no-reclamation.l0` holds 1.5 MB at 100 thousand, 1
    million, and 10 million iterations, where it reached 9.8 GB
  - the compiler compiling itself peaks at 26.3 MB, below 104.8 MB, and under
    `L0_RC_CHECK` leaves nothing live and writes the same bytes
  - both suites pass on macOS and Linux, 56 and 63, with every compiled
    program under `L0_RC_CHECK`, which was first shown to fire on a program
    built by the previous compiler
  Also measured: a streaming numberer that builds a list per line holds 1.6
  MB at 10 and 100 MB of input. Two costs recorded: the compiler takes about
  0.15 s instead of 0.04 s, since every count change is a runtime call; and
  0006's whole-input line filter still holds 2.7 GB at 100 MB, because its
  `main` passes `input` to a call not in tail position and so keeps the whole
  list alive until it returns. Releasing at last use would fix that; opened
  as [0013](0013-release-at-last-use.md).
- 2026-09-24: **correction.** The line filter's 2.7 GB is not scope-based
  release: a `main` that ignores its input peaks at the same 2,504 MB at
  100 MB, so the cost is the input list the runtime builds before `main`
  starts. See 0013, dropped on that evidence.
