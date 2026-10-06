# 0049: research: whether I/O failures should be named cases rather than codes

Kind: research
Status: done; opening reports a typed failure (0050) first
Needs: nothing

## Why

An I/O failure reaches a program as a negative `int` (spec 6.3) or as the
words `io_error` gives it, and the checker can say nothing about either. A
test of a failure that the call cannot produce type checks and never fires:

```
; Exits 2 when the directory is missing, or means to: open_write never
; returns -3 (spec 6.3), so neither test can be true, and both type check.
(def main () int
  (match (open_out "no/such/dir/notes")
    ((IoFailed why) (if (eq why "no such file") 2 1))
    ((IoOpened f)
      (if (eq (open_write "no/such/dir/notes") -3) 2 (file_close f)))))
```

```
$ tools/l0check lib/prelude.l0 lib/io.l0 tmp/0049/never.l0
ok: 3 files type check together
$ tools/l0 run tmp/0049/never.l0
$ echo $?
1
```

This is not hypothetical: 0048's first draft of its tests expected
`replace_file` on a missing directory to give "no such file", from the
habit that every system has such a code. The spec gives -3 only to
`open_read` and `rename`. A test caught it at run time; the checker could
not have, since every int compares with every int and every string with
every string. The codes also share their type with data: `read_from`
returns a byte, -1 at the end, or another negative code, so a reader tells
them apart with `(ge b 0)` and `(lt b -1)`, and a slip there type checks
too.

L0 is meant to make the checker catch what an agent gets wrong (README,
"Written for agents"). A failure that is a constructor would be: a `match`
must handle every case, and naming one that does not exist is an error.
With a failure type per operation, opening for writing would have no
"no such file" case at all, and the program above would not compile.

A rough first count (to be redone by the item): 13 comparisons of a
variable with a negative literal in `lib/`, `tests/` (outside `lang` and
`check`), and `compiler/`, and 22 uses of `io_error`'s words as string
literals in `lib/` and `tests/`.

## The question

Should the library give I/O failures names that the checker can check, and
if so, in what shape, at what cost? Weigh at least:

- one failure type for every operation, such as `(data IoFault
  (NoSuchFile) (PermissionDenied) (NotOpen) (Failed))`, against a type per
  kind of operation (opening to read, opening to write, renaming, reading,
  writing, closing), each with only the cases the spec lets it produce
- what changes for `IoOpened`, `IoLine`, `IoBytes`, and the `int` results
  of `file_close`, `file_flush`, and `rename_file`, and whether `io_error`
  keeps the words for a message
- the builtins themselves: whether they stay codes (spec 10.3's interface,
  which the seed names, is costly to change) with the library mapping them,
  or whether anything in the language needs to change
- the cost of each shape in names a program must learn and in lines at a
  call site, measured on the code that handles failures today
- what an `l0 test` of failure looks like in each shape

## Done when

- the Log has a finding: an inventory of every place in `lib/`, `tests/`,
  `compiler/`, and the roadmap's programs that compares an I/O code or
  `io_error`'s words, with counts, and which of them are wrong, vague (one
  branch for several failures that mean different things), or fine
- each shape above with its semantics, what it changes, and its cost
- a recommendation that names the first item, tooling or language, with a
  program from the inventory as its Why, or says why no change should be
  made

## Log

- 2026-10-05: opened at the user's request, from the mistake in 0048's
  tests and the question whether magic numbers cost an agent more than
  names do. The program in the Why is `tmp/0049/never.l0`, quoted in full
  above, since `tmp/` does not last.
- 2026-10-06: **finding.**
  - **Inventory, maintained code** (`lib/`, `tests/io`, `tests/unit`,
    `compiler/`; the compiler does no I/O):
    - 11 comparisons of an I/O result with a negative literal: `io_error`'s
      table (4), and 7 tests of `read_from`'s -1, the end of input, which
      shares an `int` with the bytes (`next_line_from`, `read_all_from`,
      `bytes_echo`, `filecopy`, `csvcol` ×3). All fine; they are the
      library's and tests' own byte loops
    - 35 tests of a result against 0, nearly all `file_close` and `flush`
      after writing. Fine: none needs to know which failure it was
    - 59 failure arms (`IoFailed`, `IoError`, `IoReadFailed`). 22 report
      the words, about 8 discard the failure, 19 only assert that opening
      worked, and 6 assert a particular failure by comparing strings
      (`io_test` ×4, `examples_test` ×2). One branches on which failure
      it was: `kvlog`'s `kv_load` treats a store that does not exist as
      empty with `(eq why (io_error -3))`. Correct, but coupled to the
      mapping in `io_error`, and the checker would accept the same test
      after `open_out`, which never gives -3
  - **Inventory, roadmap programs:** 35 use `IoFailed`. 0014's kvstore
    branches on `(list_eq why "no such file")` twice, and 0014 recorded it
    as limit 07 (`roadmap/0014/data-structures/limits/07-io-failure-detail-lost.l0`):
    rewording a message in the library would quietly turn every first
    `kv set` into an error. 0017 answered the other half of limit 07 with
    `IoLine`, which carries a code, and changelog "Reading a line can
    report a failure" says it chose a code because of this text matching;
    `IoFailed` kept its words
  - **So:** wrong today, none (0048's draft was caught by a test). Coupled
    to prose or to a table the checker cannot see: every site that asks
    which failure it was, all of them about opening, and all of them "a
    missing file is not an error". Failures of reads, closes, flushes, and
    renames are only ever reported or tested against 0, never told apart
  - **Shapes:**
    - *A: one failure type for every operation,* with five cases. It ties
      the check to real names, so kvstore's coupling goes, but the checker
      still accepts a case the call cannot produce, so 0048's mistake still
      compiles. A complete `match` on `open_out`'s failure must list three
      cases that cannot happen, and handle them somehow. Rejected
    - *B: a failure type per kind of open,* with only the cases spec 6.3
      lets it produce: `OpenFault` (`OpenMissing`, `OpenDenied`,
      `OpenFailed`) for opening to read, and `CreateFault` (`CreateDenied`,
      `CreateFailed`) for creating or appending. Constructor names are
      global within a group (7.1), so each type's names carry its prefix.
      `IoOpened` becomes `(IoOpened E)`, and `IoFailed` carries the case
      and the words, `(IoFailed E (list int))`. The prototype,
      `roadmap/0049/typed.l0`, written with its own types, rejects 0048's
      mistake: `error: the second argument of eq must be CreateFault, but
      this is OpenFault`. Corrected, it runs as intended
    - *C: keep the words and add predicates* such as `(io_missing why)`.
      It removes the coupling to prose and nothing else: the checker still
      accepts it after `open_out`. Rejected
  - **What B costs.** Every `IoFailed` arm gains one name, `((IoFailed f
    why) ...)`, and the checker points at each of the 47 in `lib/` and
    `tests/`; the 22 that report keep `why` unchanged. Only the library
    writes `IoOpened` as a type (its five opens and `opened`), so no program
    here writes `(IoOpened OpenFault)`. Telling failures apart is one call
    with `eq` on any type (0042), `(eq f (OpenMissing))`, and so is a test
    of one, in place of a string comparison. A program learns five
    constructor names, each shown by `l0 doc` beside the open that gives it
  - **The builtins stay codes.** Spec 10.3's interface is named by the
    seed, and nothing here needs it changed: the library's `opened` is
    already the one place a code becomes a value. No rule in `spec/L0.md`
    changes. So the magic numbers remain, at the bottom, read in one place
  - **Recommendation.** First,
    [0050](0050-open-failures-named.md), tooling: opening a file says which
    failure it was, as a case typed per kind of open (B), with kvlog's
    `kv_load` and this item's `never.l0` as its Why. After that, each only
    when a program needs to tell its failures apart, which none does yet:
    reads (`IoLine` and `IoBytes`, which carry codes), and the `int`
    results of `file_close`, `file_flush`, and `rename_file`
