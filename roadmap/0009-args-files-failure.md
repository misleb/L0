# 0009: Arguments, files, and failure

Kind: language
Status: queued
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
