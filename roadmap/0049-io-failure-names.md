# 0049: research: whether I/O failures should be named cases rather than codes

Kind: research
Status: proposed
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
