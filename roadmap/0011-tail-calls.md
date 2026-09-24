# 0011: Whether L0 guarantees tail calls

Kind: research
Status: proposed
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
