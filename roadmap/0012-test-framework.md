# 0012: A test framework in the standard library

Kind: tooling
Status: done
Needs: nothing

## Why

L0 has no test framework, only a convention: a `check` function consing
`y name` or `n name` lines onto `main`'s result. It costs agents in four
ways, each seen in this project:

- a failure does not say what was computed or what was expected
- every assertion nests inside `main`, and that nest is where closing
  parentheses get miscounted, which happened three times in the session that
  built 0008 and 0009 (`check_errors`, `is_builtin`, `io_decls`)
- one runtime error stops the whole run, and nothing can test that an error
  happens
- there is no exit status and no way to run a subset

I/O, from 0008 and 0009, is what makes all four fixable.

## Design

Agreed with the user:

- **Discovery.** `l0 test FILE...` finds every `(def test_NAME () int ...)`.
  L0 has no function values, so a program cannot list its own functions, but
  the driver can read them from the source. It generates a `main` that runs
  the test named by `(arg 0)`.
- **A process per test.** The program is built once and run once per test,
  so a runtime error fails only that test, reported with its message.
- **Assertions show got and want.** `check_int`, `check_bool`, `check_str`,
  `check_strs`, `check_true`, each writing its result as it runs and
  returning 1 on failure, so a test returns the sum. Strings are shown
  escaped, with the first differing byte.
- **TAP output**: `ok N - test_name`, `not ok N - test_name` with indented
  `#` diagnostics, a plan line, a summary, and a nonzero exit on failure.
- **Expected errors**: `test_NAME` passes if it dies with exactly the runtime
  error that `(def expect_NAME () (list int) ...)` returns.
- **Golden files**: `(check_file name got path)` compares with a file;
  `l0 test --bless` rewrites it.
- **Seeded random inputs** for property tests, in L0.
- **Filtering**: `--match TEXT` runs only tests whose names contain it.

The library is `lib/test.l0`, linked only by `l0 test`, in the prelude group.
It needs no types, so the `Io` reservation does not come into it.

Stage 0 cannot run it, so the repository's oracle-checked suites stay on the
old convention. It is for `tests/io`, the standard library's own tests,
program-writing workers, and projects made by `l0 init`.

## Done when

- `l0 test` runs a file of tests with each feature above, and its output is
  checked by a hand-written test in `tests/io`
- the shipped `l0-code` skill and `lib/examples.l0` teach it in place of the
  old convention, and `l0 init` ships it
- both suites pass, and the seed is current

## Log

- 2026-09-24: opened after 0009, before 0010, at the user's request. The user
  chose every design option above; the `expect_NAME` companion is how a test
  declares an expected runtime error, since a test that crashes cannot return
  anything.
- 2026-09-24: done; changelog "A test framework, and no language change for
  it". `lib/test.l0` has the assertions, golden files, and random inputs;
  `tools/l0 test` finds tests, generates the dispatching `main`, builds once,
  and runs each test in its own process with standard input closed. Two bugs
  found on the first run and fixed: expected errors were not recognized,
  because the discovered names were newline-separated, and `--bless` was
  silent about what it wrote. `tests/io/framework.sh` checks the whole report
  on a fixture of nine tests against hand-written expectations, plus
  `--match`, the bless cycle, and a file with no tests, and runs the shipped
  `lib/examples_test.l0`, ten tests covering each idiom. A fresh `l0 init`
  project runs them with the installed `l0 test`. Both suites pass (56 and
  63); the compiler did not change, so the seed is still current.
- 2026-09-24: the user asked whether existing tests had moved to the
  framework; they had not. The oracle-checked suites cannot, since stage 0
  cannot do I/O, and most of `tests/io` checks what a test function cannot:
  the forms of `main`, exit status, standard input, arguments, timing.
  `handles` and `order` could, and `lib/io.l0` had no unit tests at all. Now
  `tests/unit/io_test.l0` (16 tests) and `tests/unit/order_test.l0` replace
  them, run by `tools/test.sh --compiled` through `l0 test` in a scratch
  directory, against the fresh compiler through new `L0_COMPILER` and
  `L0_RUNTIME` overrides in `tools/l0`. A deliberately failing file was
  checked to fail the suite with its got and want shown.
