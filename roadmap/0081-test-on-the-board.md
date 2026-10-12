# 0081: tooling: l0 test on the virt board

Kind: tooling
Status: done, changelog "l0 test runs on the virt board, and no language
change for it"; passed on Linux arm64
Needs: 0080

## Why

The first of the two gaps [0074](0074-route-to-a-microkernel.md)'s Log
names before the kernel's own project. A project made by `l0 init` is not
done until `l0 test` passes, and a kernel's functions that make spaces,
run threads, or take interrupts do nothing on this host, where there is
no user mode (spec section 9.2). On the board, where they work, `l0 test`
refuses to run:

```
$ tools/l0 test --target virt tests/unit/io_test.l0
l0 test: runs on this host only; a test is named by an argument, and the virt board gives none
```

## The plan

The generated `main` names the test to run by its argument on this host;
on the board, which gives none, by the first line of standard input,
which the board has. The program is linked once as a board image and
booted once a test, as each test is its own process here. What the board
lacks, a test there lacks too: files, so `check_file` fails and `--bless`
is refused, and an environment, so `L0_RC_CHECK`'s leak check is not
made.

## Done when

- `tools/l0 test --target virt` runs every test of the files given on the
  board, as TAP, expected runtime errors included, and refuses `--bless`
- `tools/test.sh --virt` runs tests written with `l0 test` on the board:
  `tests/virt/unit`, tests of user mode and interrupts that need it, and
  those of `tests/unit` that need no files
- `lib/AGENTS.md` and the driver's usage say so

## Log

- 2026-10-11: opened from 0074's Log, the first of its two gaps; the
  second is 0082. Next: the driver.
- 2026-10-11: done in the driver and `lib/test.l0`. The generated `main`
  reads the test's name with `test_name_from_input`, in the library:
  first written in the generated `main`, it broke `tests/unit/shadow_test`,
  whose own `is_empty` shadowed the builtin there, as a program's
  definitions shadow every name in it but the library's own calls.
  `tools/test.sh --virt` now runs `tests/unit` on the board but for five
  files that need files or no devices, each with a `.host` file saying
  so, and `tests/virt/unit/board_test`, of a space, the timer, and an
  expected runtime error. A failing test is reported on the board as here.
- 2026-10-11: suites green: 65, 142, and `--virt` 124, from 111, with 43
  skipped, from 55, in 172 s; Linux arm64 65 and 142. Done. Next: 0082.
