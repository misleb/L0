# Worker report for 0011

I've finished the research, and I recommend that L0 guarantee **all** tail calls, not only self-recursive ones. The experiments are committed as `c8b815f` on branch `research/0011-tail-calls` in the worktree. Nothing under `compiler/`, `runtime/`, `spec/`, `lib/`, `tools/`, `tests/` or `roadmap/` was changed.

Everything below was measured on macOS arm64 with Homebrew clang 23.1.1 (the one `tools/l0ll` uses). Apple clang 21 gave identical numbers wherever I checked. Default stack is 512 MB. "No limit" means no failure up to the stated depth.

## 1. Tail position, as `emit.l0` already tracks it with `tl`

- The body of a `def` is in tail position.
- If an `(if c a b)` is in tail position, so are `a` and `b`. `c` is not.
- If a `(let n v body)` is in tail position, so is `body`. `v` is not.
- If a `(match s arms…)` is in tail position, so is every arm's expression. `s` is not.
- Nothing else is: not call or builtin arguments, not construction fields, not `and`/`or` operands.
- A **tail call** is a call to a `def` that is in tail position. Builtins in tail position are just values: `after_borrow` emits the inc/dec *after* the builtin call, and builtins can't recurse, so they don't matter here.

## 2. What happens today

### Depth at which each case exhausts the stack

| case | -O0 | -O1 | -O2 (default) | -O2, functions not inlined |
|---|---|---|---|---|
| self loop | ~11.1M | no limit to 10⁹ | no limit to 10⁹ | no limit to 10⁹ |
| mutual, arities 3↔2 | ~11.1M | no limit | no limit | no limit |
| mutual, arities 10↔2 | ~5.57M | no limit | no limit | **~22.3M** |
| mutual, arities 7↔2 | – | – | – | arm64: no limit to 10⁹; x86-64: real call (assembly only) |
| list-passing loop (release before call) | ~8.38M | no limit | no limit | no limit |
| build a list, then walk it | ~8.38M | no limit to 3×10⁷ | same | same |
| tail call in a `match` arm | ~3.34M | no limit | no limit | no limit |
| `if` nested in the tail call's argument | ~6.70M | – | no limit to 10⁸ | – |
| non-tail `(add 1 (count …))` | ~16.7M | no limit | no limit | no limit |

- **What LLVM already fixes:** at -O1 and above it turns self-recursion into loops, even through the alloca join. At -O2 the toy programs are inlined whole into `main`.
- **Why the non-inlined column matters:** it models a large program, where recursive functions aren't inlined into their callers.
- **What LLVM doesn't fix:** a non-inlined mutual tail call stays a real call whenever the callee needs stack arguments, i.e. more than 8 on arm64 or more than 6 on x86-64. So whether the same L0 program survives depends on the target.
- **Even non-tail recursion hides at -O1+:** LLVM rewrites `(add 1 (count …))` into a loop.
- **At -O0 nothing is eliminated:** every L0 call is a real call.
- **The compiler itself:** built at -O0 it needs `L0_STACK_MB=128` to compile itself; at -O2, 1 MB is enough.

### `L0_STACK_MB`
Depth scales linearly with it, about 21,800 calls per MB at -O0's 48-byte frame. Every size from 1 MB to 16 GB worked.

| `L0_STACK_MB` | self loop, -O0 | 10↔2 mutual, not inlined, -O2 |
|---|---|---|
| 1 | 15.0K | 29.9K |
| 8 | 168K | 336K |
| 64 | 1.39M | 2.78M |
| 512 | 11.1M | 22.3M |
| 4096 | 89.5M | 177M |
| 16384 | 357M | 712M |

## 3. The options

Each option is prototyped by `tailify.py`, which rewrites the IR the compiler emits and stands in for an emitter change. I also applied each option to the compiler's own IR.

**Correctness with reference counting holds for every option:**
- 207 builds ran under `L0_RC_CHECK` with 0 failures.
- For every option, the rewritten compiler at -O0 and -O2 compiled itself to output byte-identical to `stage2.ll`.
- Releasing before the call is exactly the order every option needs.
- The `tail`/`musttail` rule that the callee must not touch the caller's allocas always holds, because L0 never passes a slot's address.

**Determinism and the fixpoint:** every rewrite is a pure function of the emitted text, and running it twice gives identical bytes. None needs new L0 syntax, so each would be one bootstrap step plus a seed refresh.

- **Return directly from each branch, alone** (`--ret-direct`)
  - No effect at -O0 (same depths); -O2 already handled these cases.
  - It is the prerequisite for everything else. `proto/musttail_join.ll` shows the verifier rejects `musttail` followed by the store/branch join ("musttail call must precede a ret").
  - It also shrinks -O0 frames: the match loop went from 3.34M to 3.71M.
- **`tail` marker plus direct returns**
  - At -O0, self calls and register-argument mutual calls become jumps on arm64, x86-64 and RISC-V, and the compiler runs in 1 MB.
  - It's only a hint, though. The 10↔2 case still dies (16.7M at -O0, 22.3M not inlined), and 32-bit ARM at -O0 converts only part of it.
- **`musttail`, C convention**
  - The verifier rejects any arity mismatch (`proto/musttail_arity_ccc.ll`). Every test program failed to compile, because the prelude itself tail-calls across arities (`digits` → `digits_onto`).
  - Using `musttail` only where arities match covers 163 of the compiler's 314 tail calls.
- **`musttail` plus the `tailcc` convention**
  - Prototypes may differ (`proto/musttail_arity_tailcc.ll`).
  - All 313 tail calls in the compiler are guaranteed, including 2→10 arguments, at -O0 and -O2 on arm64 and x86-64. The -O0 compiler needs a 1 MB stack instead of 128 MB.
  - But LLVM 23.1.1's RISC-V backend rejects `tailcc` ("Unsupported calling convention"), as do 32-bit ARM at -O0 and wasm. Spec 10.2/10.4 require the same output bytes on every host, so the emitter can't choose per target.
  - `main` must stay on the C convention, so guaranteeing calls through `main` would need a small wrapper.
- **Uniform arity plus `musttail`, C convention** (`--pad-arity`, `--pad-component`)
  - Every case runs with no limit at -O0 and -O2. The compiler's output is identical and it runs in 1 MB.
  - Calls become jumps on RISC-V, 32-bit ARM and x86-64 at both levels. wasm refuses at compile time instead of miscompiling.
  - Padding every function to the module's maximum arity (9 for the compiler) costs +13% code at -O0 and +0.3% at -O2.
  - Padding per connected component of the tail-call graph pads 138 of 346 functions. Code is 1.2% *smaller* than today at -O0 (direct returns remove join code).
  - CPU time is unchanged in every variant (0.14–0.16 s).
- **Emitter turns self tail calls into loops** (`--selfloop`)
  - Portable and independent of LLVM, but self-recursion only: 200 of the compiler's 314 tail calls. Mutual cases fail exactly as today.
  - Hazard: `emit_if`/`emit_match` put join allocas where the `if` appears, often mid-function. Inside a loop, those allocate on every iteration. The nested-`if` case died at ~16.8M with SIGBUS (exit 138) and no diagnostic, because `l0_stack_check` runs once per real call, not per iteration.
  - Hoisting all allocas into the entry block fixes it. It is the most emitter work: parameter slots, the current function's name, and a second output list for hoisted allocas.

My rough estimates for the emitter work (not implemented): direct returns 30–50 lines, `tail` marker 1 line, `tailcc` about 20, global padding about 20, per-component padding 50–70, self-loops with hoisting 60–80.

## 4. Recommendation

**Guarantee all tail calls.** Implement it as direct returns in tail position plus `musttail` under the C convention, with arity padded per tail-call component and `main` wrapped.

- **Why all, not self-only:** L0 has no loops, so a state machine written as mutually recursive functions is natural L0. A self-only guarantee leaves exactly those depending on optimisation level, inlining, and the target's argument-register count, which the 7↔2 case shows differs between arm64 and x86-64.
- **Why this implementation:** the verifier enforces it, so a target that can't honour it fails at compile time and never silently grows the stack. It worked on every native target tried, and its measured cost is zero CPU and ±1% code.
- **Alternatives:** `tailcc` is simpler to emit but ties L0 to x86-64 and AArch64. Global padding is the simplest version, but a single wide function then makes every call in the program pay for it.

Proposed text for section 8, replacing the paragraph that leaves stack exhaustion unspecified:

> An expression is in *tail position* if it is the body of a `def`; the `then` or `else` of an `if` in tail position; the body of a `let` in tail position; or the expression of an arm of a `match` in tail position. Nothing else is in tail position. A *tail call* is a call to a `def` in tail position. When `f` makes a tail call, `f`'s activation ends before the callee's begins, so a chain of tail calls of any length, through functions of any arities, runs in stack bounded by the deepest nesting of calls that are not tail calls. Stack exhaustion arises only from that nesting. A program whose unbounded recursion is entirely through tail calls runs until it stops or forever.

Section 10 would also need to change:
- **10.2:** let internal functions take padded prototypes.
- **10.3:** say a tail call is emitted as `musttail call` immediately followed by `ret`, and that `if`/`match` in tail position return from each branch.
- **Allocas:** require them in the entry block.

## 5. Problems in `spec/L0.md`

- **Section 8** uses "tail position" and "eliminates tail calls" without defining either. The outcome it leaves open depends on host flags and register counts, so identical IR behaves differently on different machines.
- **The 10.3 claim "so a call in tail position stays one" is false for the emitted IR.** In an `if`/`match` branch the call is followed by a store, a branch, a load and a `ret`. At -O0 no L0 call is a tail call.
- **10.3's "runs in constant memory however long its input"** holds for the heap only. At -O0 a streaming loop dies after about 8–11M iterations.
- **10.2 fixes `i64 @l0_f_f(i64, …)` for internal functions too**, and 10.4's freedoms don't cover signatures or calling conventions. That rules out the padding and `tailcc` implementations unless revised.
- **10.4 permits allocas anywhere.** The mid-function join allocas are harmless today, but would silently break section 8's "the host reports stack exhaustion" once anything in a function loops.
- **Minor:** the spec never names `L0_STACK_MB` or its 512 MB default. Also, no clause should promise that non-tail recursion exhausts the stack at any given depth, since LLVM loops `(add 1 (count …))` at -O1 and above.

