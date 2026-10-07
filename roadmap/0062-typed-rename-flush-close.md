# 0062: rename, flush, and close say which failure it was

Kind: language
Status: done, changelog "Renaming, removing, flushing, and closing say
which failure it was"; passed on Linux arm64
Needs: 0061

## Why

0049 left reads, closes, flushes, and renames with codes "until a program
needs more"; [0055](0055-programs-round-three.md)'s failure worker needed
more. What it would have written:

```
(def rename_step ((from (list int)) (to (list int))) (list int)
  (match (rename_file from to)
    ((Renamed) "")
    ((RenameFailed fault why)
      (match fault
        ((RenameMissing) "")
        ((RenameDenied) (append "may not rename " from))
        ((RenameTargetIsDirectory) (append to " is a directory"))
        ((RenameCrossDevice) (append to " is on another file system"))
        ((RenameOther) why)))))
```

`tmp/0055/failure/hypothetical/02-typed-faults.l0`, with a `close` that
tells a full disk from a broken pipe. Today a read-only directory, a
missing directory, a directory as target, a full disk, and two kinds of
failed rename all say "input or output failed" (-5). And nothing makes a
program look: ignoring a failed `rename_file` checks and exits 0
(`limits/02b`), where opening's typed result forces a `match`.

## Done when

- decided, in the spec or the library as 0050 decided for opening, which
  causes rename, flush, and close distinguish, and whether 6.3's -5 splits
  or the runtime reports a cause beside it; the changelog says why
- the library's wrappers return typed results that `match` forces, and
  0055's rotator, archiver, and tee use them
- `CreateDenied`'s doc says what it covers, since a read-only directory
  is not it today
- the l0-bootstrap checklist, if the spec or runtime changes

## Log

- 2026-10-06: queued by 0055, with the user's agreement.
- 2026-10-07: committed part way, at the user's request (`04891eb`): spec,
  runtime, library, and every caller, with `tools/test.sh` green and
  `--compiled` not yet run.
- 2026-10-07: done.
  - decided: the causes are codes in spec 6.3, -6 to -10, read from errno
    numbered alike on both hosts, and the library types them per operation
    as 0050 did; the changelog says why, and why EDQUOT, ELOOP, and
    ENAMETOOLONG stay -5
  - `(IoDone E)` with `Done` and `NotDone`, `is_done`, `RenameFault`,
    `RemoveFault`, `WriteFault`; `OpenIsDirectory`, `CreateNoDirectory`,
    `CreateIsDirectory`; `CreateDenied`'s doc covers a directory that may
    not be written, which it now is
  - **not done: "typed results that `match` forces".** Nothing is inside
    `Done`, so an unused result still compiles, as with the `int`. Forcing
    use would be a new rule for L0 and is recorded in the changelog as not
    yet earned; the shipped skill says to look at every close of a file
    written
  - 0055's rotator, archiver, and tee, moved onto the typed results in
    `roadmap/0062/`, kept this time: the rotator also deletes its journal
    and logs past N as 0061's copy did, and passes 0055's `interrupt.py`,
    made stricter as in 0061, over 536 interrupted runs and 200 kills; the
    archiver drops its parent-directory probe and its reading of
    `OpenFailed` as a directory; the tee, piped into `head -c 10`, reports
    "the reader has gone" for standard output and copies 100 MB to its file
    whole. Their own tests pass (9, 21, 7), two of them with "no such
    directory" where they expected "input or output failed"
  - shipped skill: the new cases, `IoDone`, `is_done`, and the filter's
    `main` written with `match`; `lib/examples.l0` gains `rename_why` and
    its test; `tests/io/libdoc/index.txt` re-pinned
  - not covered by a test: -6 (a full disk) and -10 (a second file system),
    since neither can be made inside the workspace
  - both suites green (63, 122); fixpoint holds and the seed, unchanged,
    reproduces itself; `tools/linux-test.sh arm64` green (63, 122)
  - next: the language queue is empty. Open: 0059 and 0060, research, and
    0063, tooling
