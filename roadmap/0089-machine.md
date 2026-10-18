# 0089: `(machine)`, the CPU a program runs on

Kind: language
Status: done, changelog "A program asks which CPU it runs on"; passed on
Linux arm64
Needs: 0088

## Why

0087's second step. A kernel reads a thread's registers out of its
context, and the library's `trap_of` and `user_context` read them for it,
but where a register is depends on the CPU, and nothing says which CPU a
program is on (`roadmap/0089/why.l0`):

```
(def call_number ((c (array int))) int
  (array_get c 8))                        ; right on aarch64 alone
```

The IR is the same for every host (spec 9.2), so the compiler cannot
choose either.

## Done when

- the checklist in the `l0-bootstrap` skill, "Adding a builtin": spec 6,
  6.16, 9.2, 10.3; changelog; `compiler/check.l0` and `emit.l0`;
  `@l0_machine` in `l0rt.ll`; `l0_host_machine` in `host-libc.ll` (0) and
  both aarch64 parts (1); `check_errors`, `bundle_prelude`, `emit_tail`
  re-blessed; `tests/io/machine` (0 here) and `tests/virt/machine` (1 on
  the board and as a process)
- the seed refreshed, so that `lib/io.l0` can use it: 0090

## Log

- 2026-10-17: spec and changelog written ("A program asks which CPU it
  runs on"), while 0088's suites ran. Then the compiler (`bi_io`, arity
  0, `io_names`, the `declare`), `@l0_machine`, and `l0_host_machine` in
  `host-libc.ll` and both aarch64 parts. `check_errors`, `bundle_prelude`,
  and `emit_tail` re-blessed: the `declare`, `machine takes 0 arguments`,
  and `head must be a list`. `tests/io/machine` (0, with a `.host` file,
  since the board gives 1) and `tests/virt/machine` (1 on the board, as a
  process, and under the L0 kernel). Suites green: 65, 147, and `--virt`
  139 passed, 44 skipped, in 186 s. Linux arm64 65 and 147. Seed
  refreshed, and it reproduces itself. Done. Next: 0090, after the seed
  is committed.
