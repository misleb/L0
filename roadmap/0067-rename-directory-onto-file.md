# 0067: renaming a directory onto a file is not -9

Kind: language
Status: queued
Needs: nothing

## Why

The runtime breaks spec section 6.3. Renaming a directory onto a file
that exists returns -9, "no such directory", though the directory `to`
would be in does exist. A program that acts on `RenameNoDirectory`, by
reporting or creating a missing directory, is misled.

```
; rename a directory onto an existing file, and print the code
(def main () int
  (let c (rename "tmp/0067/run/adir" "tmp/0067/run/afile")
    (let w (write_line (digits c))
      0)))
```

```
$ mkdir -p tmp/0067/run/adir    # and tmp/0067/run/afile holding "x"
$ tools/l0check lib/prelude.l0 lib/io.l0 tmp/0067/repro.l0
ok: 3 files type check together
$ tools/l0 build tmp/0067/repro.l0 -o tmp/0067/repro
$ tmp/0067/repro
-9
```

The host's rename fails with ENOTDIR (20). `l0_rename` reads that errno
with `errno_missing`, which counts ENOTDIR as missing because a file
standing where a directory should be, on the way to a name, does make the
name missing. `from` exists, so the missing name is taken to be `to`'s
directory, and the result is -9.

Spec 6.3 gives -9 only when the host says `to`'s directory does not exist,
and -5 "when it cannot tell, or the reason is any other". No row covers a
`from` that is a directory, so under the spec as written the answer is -5.
Whether a directory source deserves its own code, such as -8, is a spec
question to settle first, though nothing in the repository yet asks for one.

## Done when

- the spec answer is settled: -5 as written, or a new row
- `l0_rename` tells this ENOTDIR apart from one that comes from a file in
  `to`'s path. One way is to treat it as a directory source only when
  `from` is a directory, `to` exists, and `to` is not a directory
- `tests/io` has a test of it with a directory made by its `.sh`, since L0
  cannot make one and `l0 test`'s unit tests cannot set one up
- `to` = `a_file/x`, a file on `to`'s path, still gives -9
- the changelog says what was wrong
- the l0-bootstrap checklist, and a Linux arm64 run, since ENOTDIR comes
  from the host

## Log

- 2026-10-08: found by the review that followed 0066, and reproduced on
  macOS: -9. Queued.
