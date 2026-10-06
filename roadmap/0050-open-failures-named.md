# 0050: tooling: opening a file says which failure it was, as a case the checker knows

Kind: tooling
Status: done, changelog "Opening a file says which failure it was, and no
language change for it"
Needs: 0049

## Why

[0049](0049-io-failure-names.md)'s finding. A program that must tell a
missing file from one it may not read compares `IoFailed`'s words, or a
code, and the checker accepts the test even after an open that cannot fail
that way. `kvlog` does it to treat a store that does not exist as empty:

```
(def kv_load ((path (list int))) (Result (list Entry) (list int))
  (match (open_in path)
    ((IoFailed why)
      (if (eq why (io_error -3))
          ((Ok (list Entry) (list int)) (nil Entry))
          ((Err (list Entry) (list int)) why)))
```

and this program, whose failure test can never be true since `open_write`
never returns -3, checks and exits 1:

```
(def main () int
  (match (open_out "no/such/dir/notes")
    ((IoFailed why) (if (eq why "no such file") 2 1))
    ((IoOpened f)
      (if (eq (open_write "no/such/dir/notes") -3) 2 (file_close f)))))
```

`roadmap/0049/typed.l0`, a prototype with its own types, rejects the same
mistake: `error: the second argument of eq must be CreateFault, but this is
OpenFault`.

## Done when

- `lib/io.l0` declares `(data (IoOpened E) (IoOpened IoFile) (IoFailed E
  (list int)))`, `OpenFault` (`OpenMissing`, `OpenDenied`, `OpenFailed`) for
  `open_in` and `open_in_bytes`, and `CreateFault` (`CreateDenied`,
  `CreateFailed`) for `open_out`, `open_appending`, and `open_out_buffer`,
  each case documented with the spec 6.3 code it stands for; the words stay
  as `io_error` gives them
- every `IoFailed` arm in `lib/`, `tests/`, and the examples takes the new
  field; `kvlog`'s `kv_load` tests `(eq f (OpenMissing))`, and the tests
  that compared a failure's words compare its case
- a test that `(eq f (OpenMissing))` after `open_out` is a type error, in
  `tests/compiler` or as a checked failure, and tests of each case an open
  can return
- `tests/io/libdoc/index.txt` re-pinned, the `l0-code` skills and
  `lib/examples.l0` show telling failures apart, the changelog says why,
  superseding the words-only choice that "Reading a line can report a
  failure" kept, and both suites are green
- `roadmap/0049/` deleted

## Log

- 2026-10-06: proposed by 0049.
- 2026-10-06: done.
  - `lib/io.l0`: `(IoOpened E)`, `OpenFault`, `CreateFault`, documented
    with the spec 6.3 codes; `opened` is now `opened_in` and `opened_out`,
    the one place each kind of open's code becomes a case
  - the 47 `IoFailed` arms in `lib/` and `tests/` bind `fault` too, each
    found by the checker; `kvlog`'s `kv_load` tests `(eq fault
    (OpenMissing))`; `io_test`'s four reason tests check the case and the
    words
  - `tests/io/open_faults`: every case each open can return, by its name
    and words; the denied cases only where permission bits are enforced,
    as `filecopy.sh` does, and they were (checked by hand on macOS); and
    0049's mistake rejected by `l0 check` with the CreateFault/OpenFault
    message
  - `lib/examples.l0` gains `lines_or_none`, a missing file read as no
    lines, with a test; the shipped `l0-code` skill says to test the case,
    not the words; `tests/io/libdoc/index.txt` re-pinned, a diff of
    exactly the new and changed entries
  - both suites green (63, 111); `roadmap/0049/` deleted. No Linux run:
    only the library and tests changed, and Docker is down, so 0045's runs
    are still owed
  - next: nothing queued. 0049's later candidates, each when a program
    needs to tell their failures apart: reads (`IoLine`, `IoBytes`), and
    the `int` results of `file_close`, `file_flush`, and `rename_file`
