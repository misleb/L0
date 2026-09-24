# 0017: Library and tool fixes from 0014

Kind: tooling
Status: queued
Needs: nothing

## Why

[0014](0014-programs-round-two.md)'s workers found these, and none needs a
language change. The user chose to fix them before the next goal.

- `read_line` and `file_read_line` in `lib/io.l0` treat every negative result
  as end of input, so a failed read looks like a short file. All three
  workers hit it; linediff, minigrep, and kvstore each wrote their own reader.
- `l0 test` cannot show a leak: `L0_RC_CHECK` reports on standard error with
  exit status 0, and `l0 test` shows standard error only for failing tests.
  Two workers found it; `0014/data-structures/rc_check_tests.sh` is one
  workaround.
- `tools/l0check` puts `lib/test.l0` in the program group and `l0 test` does
  not, so a test that defines `pass`, `fail`, or `read_all` passes one and
  fails the other. Two workers.
- The shipped `l0-code` skill names `l0/L0.md` and `l0 check`, which exist
  only in an `l0 init` project, and still calls L0 pure. All three.
- `tools/l0 run` treats every argument as a source file, so a program that
  takes arguments must be built first.
- The skill never says a program's `main` must be in its own file, since
  `l0 test` supplies a `main`.
- The prelude's `length`, `append`, and `args_from` are not tail recursive;
  `length` of 10 million elements uses 320 MB of stack.
- The checker's "unknown type" error does not name the type.
- `is_lower` is true for `_`, which the skill does not say.

## Done when

Each is fixed or explicitly declined here with the reason, with a test for
each fix, and both suites green.

## Log

- 2026-09-24: opened from 0014.
