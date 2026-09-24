# 0001: How to shed the C runtime

Kind: research
Status: done
Needs: nothing

## Why

Every compiled L0 program, including the compiler, links two C files:
`runtime/l0core.c` (242 lines) and `runtime/l0rt.c` (25 lines). They are
compiled by `tools/build.sh` and `tools/install.sh`, and linked by `tools/l0`,
`tools/l0ll`, and `tools/test.sh`. The goal is that no C source goes into a
compiled program. libc may still be called, as the interface to the
operating system.

What the C does today, and what each part needs from outside L0:

| Job | Functions | Needs from the OS |
|---|---|---|
| lists and data blocks | `l0_cons`, `l0_head`, `l0_tail`, `l0_is_empty`, `l0_data_new`, `l0_data_set`, `l0_data_tag`, `l0_data_get` | only an allocator |
| arithmetic that can fail | `l0_div`, `l0_mod` | only error reporting |
| runtime errors | `l0_runtime_error`: message to stderr, exit 70, stdout never flushed | `write`, `_exit` |
| allocation | bump arena in 64 MB chunks, 16-byte aligned, never freed | `malloc` or `mmap` |
| host I/O | `l0_read_stdin_list`, `l0_write_result` (bytes, decimal `int`, `true`/`false`) | `read`, `write` |
| deep recursion | `l0_run_on_big_stack`: 512 MB pthread stack, `L0_STACK_MB`, SIGSEGV/SIGBUS on an alternate stack reported as "stack exhausted" | `pthread_*`, `sigaltstack`, `sigaction`, `getenv` |
| entry point | `main` in `l0rt.c`: read, call `@l0_f_main`, write | none |

The first three rows are small enough that the compiler could emit them
directly as IR. The last four are where the design questions are.

## Questions to answer

1. **Where the runtime code lives.** Options: IR text the compiler emits into
   every program; L0 source, which needs new primitives (raw memory access,
   calls to external functions such as libc); or a mix, with a few primitives
   in emitted IR and the rest in L0. Which approach advances the memory
   management and I/O goals, rather than only relocating the C? Is emitted IR a
   useful first step toward L0 source, or wasted work?
2. **Deep recursion.** The compiler and every program rely on the 512 MB stack.
   Options: call pthread from emitted IR; guarantee tail calls
   (`musttail`) in spec section 8 and measure how deep the compiler still
   recurses in non-tail position on its own source; set the main thread's
   stack size at link time, after checking what macOS and Linux each actually
   honor, and up to what limit. Stack
   exhaustion must still be reported as a runtime error (section 8), which
   needs a signal handler on an alternate stack.
3. **The transition.** The seed `bootstrap/stage2.ll` declares the section 10.3
   functions and is linked against the C objects by `tools/install.sh`. Once
   the compiler emits its own definitions, the C definitions of the same names
   collide at link time. Find an order, with names or linkage chosen, in which
   every commit still builds from a fresh clone, and say where the two-step
   rule and seed refreshes fall.
4. **What stays C.** `stage0/l0i.c` includes `l0core.h` and links `l0core.o`.
   Stage 0 is frozen and its runtime cannot move under it. Confirm that
   `runtime/l0core.c` becomes stage-0-only, and decide whether it moves under
   `stage0/`. The six hand-written tests in `tests/backend/` link the runtime
   too, and pin the section 10 ABI; say what happens to them.
5. **The spec.** What sections 8, 9, 10.1, 10.3, and 10.4 must say afterward.
   In particular, 10.3 is a fixed interface to a runtime that will no longer be
   a separate artifact.

## Done when

- each question above has an answer recorded in the Log, with the option chosen
  and the reason
- the answers are turned into language items in `INDEX.md`'s queue, each one a
  single bootstrapped change, in an order that keeps a fresh clone buildable
- the queue's last item has a checkable end state: `nm` on a compiled program
  shows no symbol defined by `runtime/`, `tools/install.sh` and `tools/l0`
  compile and link no C for compiled programs, and both test suites and the
  bootstrap pass from a fresh clone

## Log

- 2026-09-23: opened. The inventory above comes from reading `runtime/` and
  the four scripts that link it. Scope settled with the user: no C source in
  compiled programs, libc allowed. Not started beyond that. Run 0002 alongside
  this; its limits feed question 1.
- 2026-09-23: **measured the stack.** At `-O2` the compiler compiles itself
  byte-identically on a 1 MB stack, because LLVM's tail-call pass turns its
  recursion into loops, including accumulator recursion like
  `(add 1 (len (tail l)))`. Recursion LLVM cannot rewrite, such as rebuilding a
  list through `cons`, costs 32 bytes a frame on arm64: 8 MB holds a 100 KB
  input and not a 1 MB one, and 512 MB holds 10 MB. So the big stack exists for
  user programs, not the compiler, and must stay. macOS honors
  `-Wl,-stack_size` for the main thread up to 512 MB on arm64. Linux has no
  link-time equivalent, so a thread is the portable answer.
- 2026-09-23: **built a prototype**, [0001/proto-rt.ll](0001/proto-rt.ll): the
  whole runtime as hand-written LLVM IR that calls only libc, with no target
  triple. Designed around what differs between platforms: it uses file
  descriptors rather than `FILE*` (whose symbol names differ), no varargs,
  and an opaque 128-byte buffer for `pthread_attr_t`. It avoids signal
  handling entirely, because `struct sigaction`, `SA_ONSTACK`, and `SIGBUS`
  all differ between macOS and Linux, and target-independent IR cannot encode
  them. Stack exhaustion is instead an explicit check: the thread records a
  limit on entry, and each L0 function calls `@l0_stack_check` first.
  Results, on macOS arm64 and on Linux aarch64 (Ubuntu 24.04, glibc, clang
  18, in Docker), identical on both:
  - all 30 compiled test programs pass against their existing expectations,
    including every runtime error case ([0001/run.sh](0001/run.sh) reproduces
    this after `tools/test.sh --compiled`)
  - the compiler linked against it compiles itself byte-identically
  - stack exhaustion is reported at exactly the depths the C runtime reports
    it, for every `L0_STACK_MB` tried
  - no symbol from `runtime/` remains; the only undefined symbols are 13 libc
    functions
  - no measurable speed difference
  Linux x86_64 is untested. Clang 18 also assembled IR from a compiler whose
  seed was cut with clang 22, which is evidence on the seed's LLVM-version
  sensitivity.
- 2026-09-23: **answers.**
  1. *Where the runtime lives:* for shedding the C, a hand-written IR file,
     `runtime/l0rt.ll`, replacing both C files and exporting the same names.
     Emitting it from the compiler was considered and rejected for now: it
     buries the runtime in string literals in `emit.l0`, and loses the seam
     that section 10.3 already is. That seam is exactly where a runtime
     written in L0 can later slot in, behind the same names, once L0 can
     express memory and I/O. Whether and how to write it in L0 waits on
     0002's limits, and is the start of the memory-management goal rather
     than part of this one.
  2. *Deep recursion:* keep the 512 MB thread and `L0_STACK_MB`, created
     through pthread from IR. Replace the signal handler with the explicit
     check, which is portable and needs no platform constants. Guaranteed tail
     calls are not needed for this goal.
  3. *The transition:* one bootstrapped change, and no two-step rule, because
     the compiler's own source uses nothing new. The existing seed declares
     the section 10.3 names externally, and `l0rt.ll` defines them, so the
     seed links against it unchanged; it lacks the stack checks, which only
     matters if the seed itself overflows, and it compiles the compiler on
     1 MB. The seed is then refreshed so that it carries the checks.
  4. *What stays C:* only stage 0. `runtime/l0core.c` and `l0core.h` become
     stage-0-only and move under `stage0/`, which changes `tools/build.sh`'s
     include path and not `l0i.c`. `runtime/l0rt.c` is deleted. The six
     backend tests keep pinning the section 10 ABI, linked against `l0rt.ll`.
  5. *The spec:* section 10.3 gains `@l0_stack_check`, which the append-only
     rule allows, and says the runtime is LLVM IR calling libc. It must also
     say that every L0 function calls the check on entry. Sections 8, 9,
     10.1, and 10.4 keep their behavior; section 8's stack-exhaustion
     sentence stays true.
  Opened [0003](0003-ir-runtime.md) and [0004](0004-retire-c-runtime.md) from
  these. Question 1's longer-term half stays open until 0002 reports.
- 2026-09-23: 0003 landed, so no C source goes into a compiled program. 0002
  reported, answering question 1's longer-term half: writing the runtime in
  L0 would need at least memory access, static storage, and calls to C
  functions, and at the entry point also symbol naming, C types, and function
  values. None of that is needed any more to shed the C, which is done. So
  whether L0 grows those primitives is no longer a question about the runtime.
  It is a question about what the memory-management and I/O goals mean for L0
  programs, and it is the next item's to answer. Done.
