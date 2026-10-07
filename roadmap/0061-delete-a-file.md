# 0061: delete a file

Kind: language
Status: done, changelog "Deleting a file"; passed on Linux arm64
Needs: 0058

## Why

[0055](0055-programs-round-three.md)'s failure worker: a file cannot be
deleted.

```
(def main () int
  (remove_file "out.partial"))
```

```
$ tools/l0 check tmp/0055/failure/limits/03-delete.l0
tmp/0055/failure/limits/03-delete.l0:6:3: error: unknown function remove_file
```

A failed pack leaves `OUT.partial` behind, an unpacker leaves a file it
could not finish, and the log rotator keeps its journal forever and cannot
drop logs older than N; it can only rename them.

## Done when

- the spec has the builtin, its results in 6.3's table (a missing file, a
  denied one, a directory, any other failure), and what is promised if the
  program stops partway; the changelog says why, and why not directories
- the library wraps it, as it does `rename`
- 0055's rotator and archiver clean up after themselves with it
- the l0-bootstrap checklist

## Log

- 2026-10-06: queued by 0055, with the user's agreement.
- 2026-10-07: done.
  - spec 6.3: `(remove path)`, 0, -3, -4, or -5; a directory is -5 and
    stays, a link goes rather than what it leads to, deleting is one step,
    and an open handle keeps working until closed. The table in 6 and 6.3's
    table of codes name it, and 10.3 gains `@l0_remove`
  - runtime: `unlink`, then on a failure `opendir` before errno, since macOS
    refuses a directory with EPERM; 0057's errno reading gives -3 and -4
  - compiler: a path builtin of one argument, borrowed as `rename`'s are;
    the compiler's source uses none of it, so one step, and the seed is
    refreshed
  - library: `remove_file`; `lib/examples.l0`'s `replace_file` deletes its
    half-written file when the write or the rename fails, with a test; the
    shipped skill says so under updating a file
  - tests: `tests/io/remove` (a file, nothing there, a missing directory, a
    file as a directory, a directory refused and kept, a link to a file and
    one to a directory, a handle still reading, and a directory that may
    not be written, where that is enforced); two checker cases;
    `bundle_prelude`, `emit_tail`, `check_errors`, and
    `tests/io/libdoc/index.txt` updated for the new declaration, cases, and
    `remove_file`, and nothing else
  - 0055's programs, changed in scratch copies that were not kept, since
    `roadmap/0055/` stays as history and 0062 changes the same programs
    again from there: the rotator drops logs past N and deletes its
    journal last; 0055's `interrupt.py`, changed to require that a finished
    rotation leaves neither, passes 536 interrupted runs and 200 kills. The
    archiver deletes `OUT.partial` when packing fails; a pack whose final
    rename fails leaves nothing. Both programs' own tests still pass (9, 22)
  - both suites green (63, 122); fixpoint at 1,238,540 bytes, seed
    refreshed and reproduces itself; `tools/linux-test.sh arm64` green
    (63, 122); amd64 not run
  - next: 0062, which starts from 0057's errno and now has four calls
    returning codes to type: rename, remove, flush, and close
