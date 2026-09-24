# 0015: Guarantee every tail call

Kind: language
Status: done
Needs: 0011

## Why

From [0011](0011-tail-calls.md): with an 8 MB stack, a self-recursive loop
built at `-O0` exhausts it at 1 million iterations, and so does a tail call
between a 10-argument and a 2-argument function at the default `-O2` when
neither is inlined. Whether an L0 loop runs forever or dies depended on the
optimization level, inlining, and the target's argument registers. The user
chose to guarantee all tail calls, by 0011's recommendation: direct returns
in tail position, `musttail`, and arities padded per tail-call component.

## Done when

- spec section 8 defines tail position and guarantees tail calls, and 10.2
  to 10.4 say how they are emitted
- a test fails with the old compiler and passes with the new at `-O0` on a
  small stack
- both suites green, fixpoint holds, seed refreshed

## Log

- 2026-09-24: done in one bootstrapped change, since it needs no new syntax
  and the compiler uses no new feature. Changelog "A tail call uses no
  stack".
  - `compiler/emit.l0`: `if` and `match` in tail position return from each
    branch; a call to a function there is `musttail call` then `ret`; each
    function's arity is its component's widest, found by raising both ends
    of every tail-call edge until nothing changes; `main` is a wrapper around
    `@l0_f_main.body`.
  - `tests/io/tail_calls` builds its program at `-O0` and runs a million
    iterations of six shapes on a 1 MB stack. Built by the seed it exhausts
    the stack; built by the new compiler it passes. `tests/compiler/emit_tail`
    pins padding, direct returns, and the wrapper in a golden, and
    `bundle_prelude`'s golden changed by exactly the wrapper and one
    `musttail`.
  - `tests/io/*.sh` scripts now also receive the IR the executable was linked
    from.
  - All eight of 0011's cases run 10 million iterations on 8 MB at `-O0` and
    at `-O2` with nothing inlined. The compiler at `-O0` compiles itself on
    1 MB under `L0_RC_CHECK`, identically. Both suites pass on macOS arm64
    and on Linux aarch64 and x86-64 (clang 18).
