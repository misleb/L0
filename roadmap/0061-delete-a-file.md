# 0061: delete a file

Kind: language
Status: queued
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
