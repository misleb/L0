# 0011: Whether L0 guarantees tail calls

Kind: research
Status: done
Needs: nothing

## Why

From [0006](0006-ordinary-programs.md): the word counter exhausts the stack on
10 MB of input when built at `-O0`, and completes at `-O1` and above. Long
L0 loops survive only because LLVM happens to turn tail calls into jumps.
Section 8 leaves tail calls unspecified and never defines tail position, and
a general-purpose L0 will have long-running loops.

## Questions to answer

1. What "tail position" means in L0, precisely, for `if`, `let`, and `match`.
2. Whether LLVM's `musttail` can serve, given that it requires caller and
   callee signatures to match, and L0 functions differ in arity. What the
   alternatives cost: a uniform calling convention, the emitter turning
   self-recursion into loops itself, or a trampoline.
3. Whether reference counting (0010) interferes, since decrements after a
   call take it out of tail position.

## Done when

- a recommendation recorded here, and a language item opened if it calls for
  one

## Log

- 2026-09-23: opened from 0005's recommendation. Can run at any time; it
  interacts with 0010.
- 2026-09-24: 0010 landed, releasing bindings before a tail call. Launched a
  `best-of-n-runner` worker to measure what LLVM does today at -O2 and -O0,
  and   to prototype musttail, the tail marker, the emitter turning self tail
  calls into loops, and returning directly from a branch.
- 2026-09-24: **the worker reported**; its scripts, cases, prototypes, and
  results are copied into [0011/](0011/), and `0011/README.md` is its full
  write-up. Re-checked in the main tree:
  - `musttail` followed by the join's store and branch is rejected ("musttail
    call must precede a ret"), and under the C convention across different
    arities ("cannot guarantee tail call due to mismatched parameter counts");
    under `tailcc` the same call is accepted
  - a self-recursive loop built at `-O0` exhausts an 8 MB stack at 1 million
    iterations
  - at the default `-O2`, a tail call between a 10-argument and a 2-argument
    function that are not inlined also exhausts 8 MB at 1 million iterations,
    so even the default build does not keep a realistic program's loops flat

  *Findings*, from the worker and not all re-checked: tail position is
  exactly what `emit.l0`'s `tl` flag tracks. LLVM at `-O1` and above loops
  self-recursion but leaves a mutual tail call real whenever the callee needs
  stack arguments, more than 8 on arm64 and 6 on x86-64, so the same program
  behaves differently by target. `tailcc` with `musttail` guarantees every
  tail call on arm64 and x86-64 but is rejected on RISC-V, 32-bit ARM at
  `-O0`, and wasm, which spec 10.2's same-bytes-on-every-host rule forbids
  choosing per target. Padding arities under the C convention, per connected
  component of the tail-call graph, worked on every native target tried, at
  no measured CPU cost and 1.2% less code at `-O0`; the verifier then makes
  any target that cannot honor it fail at compile time rather than grow the
  stack. Every option passed 207 builds under `L0_RC_CHECK`, and each
  rewritten compiler compiled itself byte-identically. Turning self tail
  calls into loops in the emitter covers 200 of the compiler's 314 tail
  calls and needs allocas hoisted into the entry block, or a loop through a
  mid-function `if` allocates a join slot per iteration and dies without a
  diagnostic.

  *Its recommendation:* guarantee all tail calls, by returning directly from
  each branch in tail position and emitting `musttail` with arities padded
  per tail-call component, `main` wrapped, and allocas in the entry block.

  *Spec fixes made now*, since they were false whatever is decided: 10.3's
  "so a call in tail position stays one", and its "constant memory" for a
  streaming program, which holds for the heap only.

  Waiting on the user's decision.
- 2026-09-24: the user chose to guarantee all tail calls, as recommended.
  Implemented as [0015](0015-guarantee-tail-calls.md). The worktree and its
  branch are removed, with the user's approval.
