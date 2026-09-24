# 0005: Which route to memory management and I/O

Kind: research
Status: active
Needs: nothing

## Why

The goal is a general-purpose L0 that manages memory and does I/O. Today
memory is never freed, so a program's memory is proportional to everything it
ever allocated, and its only contact with the world is one read of stdin to end
of file and one write of the result. Both are done by `runtime/l0rt.ll`, which
L0 code cannot reach.

There are two routes, and they lead to different languages:

- **Systems.** L0 gains the primitives [0002](0002-runtime-in-l0.md) found
  missing: loads and stores at an address, static storage, and calls to C
  functions, with C types. The runtime then moves from IR into L0 piece by
  piece, and memory management and I/O are written in L0. `0002/limits/` is
  the list and `0002/hypothetical/` the first draft of the code.
- **Language.** L0 programs gain safe facilities, such as memory that is
  reclaimed, and reading, writing, and opening streams, implemented in the IR
  runtime behind new builtins. L0 code never touches raw memory.

A mix is possible, such as the primitives confined to privileged code and
safe facilities built on them.

## Questions to answer

1. **Safety.** Spec section 8 promises that a program which type checks
   cannot read uninitialized memory. Raw loads and stores end that for any
   code that can use them. Can they be confined to privileged code (a third
   group beside the prelude, section 7.1), and what does confining them cost
   the checker and the bootstrap?
2. **Purity.** Any I/O beyond the single read and write moves the purity
   boundary. Price it against what the spec already names: sections 1 and 8,
   and the arena paragraph in 10.3. Read "Output before input is an accepted
   blocker" in the changelog, which has the measurement and the costs already
   argued for one case, and whose preferred shape is to be re-argued rather
   than inherited.
3. **Reclamation.** What would make memory proportional to live data: a
   collector, reference counting, regions or arenas the program controls, or
   explicit freeing? Which of those can the checker keep safe, and which ones
   does each route even allow?
4. **The agent as author.** The goals say L0 is written for agents, so what
   matters is whether code comes out correct and whether the checker catches
   it when not. Which route leaves more errors for the checker to catch?
   Ground this in [0006](0006-ordinary-programs.md)'s programs rather than in
   preference.
5. **What each route costs the project.** The stage-0 oracle cannot run
   programs that use new features, so how much of the differential suite does
   each route leave covering the new code? What does each do to the seed and
   to the runtime interface's append-only rule?

## Done when

- a recommended route, with the reason, recorded in the Log
- the first language items for it opened in the queue, each one a single
  bootstrapped change with code in its Why
- the user has agreed to the route, since it decides what kind of language L0
  becomes

## Log

- 2026-09-23: opened after 0002 and 0003. The user chose to research both
  routes before any language change.
- 2026-09-23: **preliminary answers to questions 1, 2, 3, and 5**, from the
  spec and one measurement. Question 4 waits on 0006, and so does the
  recommendation.

  *A measurement.* The compiler compiling itself peaks at 74.5 MB resident for
  97 KB of source, about 765 bytes per source byte, all of it held until
  exit. Tolerable today, and proportional to the source, but it is the
  largest L0 program there is and it shows the arena's cost directly.

  *A property that decides question 3.* An L0 heap can never contain a cycle.
  There is no mutation, evaluation is strict, and `let` cannot define a
  recursive value (section 5.3), so every object points only to objects that
  existed before it. Reference counting would therefore reclaim everything,
  with no cycle collector. This is the property Lean 4 and Koka build on.

  1. *Safety.* Raw loads and stores end section 8's guarantee for any code
     that can use them. They can be confined: the prelude mechanism of 7.1
     already tells the checker which group a declaration is in, so a third
     group allowed to call unsafe builtins is a small checker change plus a
     bundle header line. But confinement does not remove limits 06 (symbol
     names), 09 (a library group cannot see `main`), or 10 (code beneath the
     allocator must not allocate), and 10 is a discipline the checker would
     have to enforce too. The language route keeps the guarantee whole.
  2. *Purity.* Both routes move the boundary. A C call is an effect in
     expression position, so the systems route costs at least what I/O
     builtins would. Section 8 already pins evaluation order left to right, so
     effects in expression position are well defined; what is lost is the
     freedom to reorder, which the compiler does not use and LLVM cannot apply
     to opaque calls anyway. The alternative that keeps `main` pure, the host
     loop from "Output before input", fixes prompting but not files or
     arguments.
  3. *Reclamation.* Weighed against what L0 is:
     - reference counting: complete, because the heap is acyclic. Needs no
       surface syntax at all: the compiler emits increments and decrements,
       and the runtime frees. Needs the emitter to keep the types it now
       discards, and each heap block to say which of its words are pointers,
       since a cons cell's head may be an `int` or a pointer. It also allows
       updating in place when a count is one.
     - tracing collection: needs roots and layouts. Every value is an
       untyped `i64` at run time (section 10.1), so it would be conservative
       unless the compiler emits type information it currently drops.
     - regions, explicit freeing, or linear types: safe only with new type
       rules, and explicit freeing not even then. Explicit freeing is the only
       option the systems route offers without more type work.
  5. *Project costs.* Reclamation by reference counting changes nothing a
     program can observe except its memory, so the whole differential suite
     keeps judging it against stage 0. New I/O builtins cannot run under
     stage 0, so tests using them have no oracle, as the l0-bootstrap skill
     already expects of new features. A runtime moved into L0 would still be
     judged by stage 0 through the programs it runs, but moving it hits limit
     06: the compiler would have to emit L0 functions under the fixed names in
     10.3. Reference counting adds runtime functions, which the append-only
     rule allows.

  *Leaning, not yet a recommendation:* the language route, with reclamation
  by reference counting first, since it is invisible to programs, keeps the
  oracle, and uses a property L0 already has; then I/O as builtins in
  expression position under section 8's ordering. The systems primitives
  would wait until a program needs them. 0006 may overturn this.
