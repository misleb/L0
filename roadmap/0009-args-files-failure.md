# 0009: Arguments, files, and failure

Kind: language
Status: done
Needs: 0008

## Why

From [0006](0006-ordinary-programs.md). Filecopy cannot be written: there are
no command-line arguments (limit 05), no files (limit 06), and no way to fail
except a crash with a fixed message and status 70 (limit 07). The checker
confirms the missing pieces:

```
0006/limits/06-no-files.l0:10:4: error: unknown function 'read_file'
0006/limits/06-no-files.l0:13:4: error: unknown function 'write_file'
0006/limits/07-no-failure-report.l0:11:4: error: unknown function 'fail'
```

`0006/hypothetical/06-no-files.l0` is the program that should have been
possible. Its central design choice is the reason 0005 chose the language
route: opening a file returns a data type with a failure case, so exhaustive
`match` rejects a filecopy that forgets it.

## Open questions for this item

- How a predeclared result type fits section 7.1, which does not group type
  or constructor names: a predeclared `Opened` breaks every program that
  already used the name. "Output before input" in the changelog rejected a
  predeclared `Turn` for exactly this reason.
- What a file handle is, given that every value is one `i64` (section 10.1).
- Exit status and standard error: a builtin, or part of `main`'s result.

## Done when

- the checklist in the `l0-bootstrap` skill
- filecopy is written in L0, checks, copies a file named on its command line,
  and reports a missing file with a nonzero status

## Log

- 2026-09-23: opened from 0005's recommendation.
- 2026-09-23: 0008 settled part of this. A `main` with no parameters returns
  the exit status, so a program can already fail with a status of its
  choosing. What remains is arguments, files, and standard error. The builtin
  style 0008 chose, `read_byte` returning -1 rather than a data type, avoided
  the predeclared-type question for now; file operations that fail will not
  be able to.
- 2026-09-23: started. The user chose to reserve type and constructor names
  beginning with `Io` and an uppercase letter for the standard library, over
  grouping type names (about 44 resolution sites, against 7.1's stated
  reasons) or accepting collisions. Design:
  - builtins over integer handles into a runtime table, with 0, 1, and 2 the
    standard streams, so `read_byte` is `(read_from 0)`: `arg_count`, `arg`,
    `open_read`, `open_write`, `read_from`, `write_to`, `close`
  - failures are negative codes, a few of them specified, since a builtin
    cannot return a data type without predeclaring it
  - `lib/io.l0` declares `IoFile` and `IoOpened`/`IoFailed` and wraps the
    builtins, so a `match` on opening a file must handle failure
  - the runtime stays portable: `open` with read-only, which is 0 on both
    platforms, and `creat` for writing, since `O_CREAT` and `O_TRUNC` differ
    between macOS and Linux; `errno` is not reachable portably, so the reason
    for a failure comes from `access()`
- 2026-09-23: done; changelog "Files, arguments, and names reserved for the
  standard library". Filecopy is `tests/io/filecopy`, and `filecopy.sh`
  checks a byte-exact 300 KB copy and each failure's message and status; it
  rejects a program that does not really copy. Built with `tools/l0`, it
  copies, reports a missing file with status 1, and a usage error with 2.
  Along the way:
  - `tools/l0check` and `tools/l0c` had to learn the prelude group, or the
    library's own `IoFile` was rejected as reserved; they now group
    `lib/prelude.l0` and `lib/io.l0` whenever `lib/io.l0` is given, through
    a shared `tools/bundle.sh`
  - `examples_check` now checks the examples with the libraries as the
    prelude, finding where the examples begin by their header line
  - on Linux in Docker, the permission case failed because the bind mount
    ignores permission bits; `filecopy.sh` now checks it only where they are
    enforced, and both suites pass there off the bind mount
  Both suites pass (56 interpreted, 62 compiled) on macOS and Linux, the
  fixpoint holds, the seed is refreshed, and a fresh copy installs and builds
  filecopy.
