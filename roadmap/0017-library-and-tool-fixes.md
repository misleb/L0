# 0017: Library and tool fixes from 0014

Kind: tooling
Status: done
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
- 2026-09-24: done; changelog "Reading a line can report a failure, and no
  language change for it". Each finding:
  - *read_line's errors:* fixed by adding `next_line` and `file_next_line`,
    returning `IoLine`; the old two keep their meaning and say so. Tested in
    `tests/unit/io_test.l0` on a file, a directory (`IoError -5`), and a file
    open for writing (`IoError -2`).
  - *leaks invisible:* fixed. `l0 test` runs every test with `L0_RC_CHECK=1`
    and fails one whose run reports blocks still live. `tests/io/framework.sh`
    shows it with a stand-in compiler that drops every `l0_dec`.
  - *grouping of `lib/test.l0`:* fixed in `tools/bundle.sh`, and
    `l0 check --test` added; both tested in `framework.sh` on a test file that
    shadows `read_all`.
  - *skill paths:* the in-repository `l0-code` skill now maps the shipped
    skill's `l0/` paths onto `spec/` and `lib/`; the shipped skill no longer
    calls L0 pure.
  - *`l0 run` arguments:* fixed, as `l0 run FILE... -- ARG...`, and the
    program's exit status is the driver's; tested in `framework.sh`.
  - *`main` in its own file:* now said in the shipped skill's testing section.
  - *non-tail prelude functions:* `length`, `append`, and `args` fixed.
    `tests/io/prelude_depth` runs a million elements at `-O0` on a 1 MB
    stack; with the old prelude it exhausts the stack.
  - *unnamed "unknown type":* only the parser's message for a lowercase word
    in type position lacked the name; it now gives the word and what a type
    can be. New `tests/check/type_lowercase`; `parse_errors`' golden changed
    by exactly those two lines.
  - *`is_lower` and `_`:* declined as a change, since it tests what may start
    a lowercase name and the lexer relies on that; the shipped skill says so.

  Both suites green (58 and 67), fixpoint holds, seed refreshed, since the
  prelude the compiler is built from changed.
