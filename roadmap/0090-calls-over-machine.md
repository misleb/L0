# 0090: the library and the L0 kernel read a system call over `(machine)`

Kind: language
Status: done, changelog "The library reads a system call wherever the CPU
keeps it"
Needs: 0089

## Why

0087's third step, the use 0089's builtin is for. `trap_of` read `x8` as
word 8 and `user_context` wrote sp to word 31, and the L0 kernel read and
answered its processes' calls by aarch64's words in about 25 places.

## Done when

- `call_number`, `call_arg`, and `call_result` in `lib/io.l0`, and
  `trap_of` and `user_context` over the same table; spec 6.13 names them;
  `lib/AGENTS.md` says so; `tests/io/libdoc/index.txt` regenerated
- `tests/virt/user/kernel.l0` reads no register by its word
- `tools/test.sh`, `--compiled`, and `--virt` green, with no change in
  what any test prints

## Log

- 2026-10-18: written after 0089's commit, 26af0e1. `trap_of_exception`
  is `trap_of_aarch64`, and the table is three functions of the CPU's
  number. Suites green: 65, 147, and `--virt` 139 passed, 44 skipped, as
  after 0089. No compiler change, so no new seed. Done.
