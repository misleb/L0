# 0062: rename, flush, and close say which failure it was

Kind: language
Status: queued
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
