# 0022: The standard library documents itself, and l0 init copies no reference

Kind: tooling
Status: done
Needs: nothing

## Why

`l0 init` copied the specification, the examples, and the three library
files into every project, so a project made before a toolchain upgrade read
a library that no longer matched the compiler building it. The library is
going to grow, and agents should learn what it offers without reading its
source or the specification carrying library details. The user chose, from
four options: doc comments in the library, read by an `l0 doc` command from
the installed library; `l0 init` to copy only `AGENTS.md` and the skill; and
this before 0018, since 0018 to 0020 add library functions to document.

## Done when

- every public definition of `lib/prelude.l0`, `lib/io.l0`, and `lib/test.l0`
  has a `;;` comment, and `l0 doc` shows an index, one file, one name, or a
  search, from the library the driver links
- `l0 spec` and `l0 examples` show the installed copies, and `l0 init`
  copies nothing else
- the shipped skill, `lib/AGENTS.md`, and the README use the commands
- a test pins the index and each lookup

## Log

- 2026-09-24: done; changelog "The standard library documents itself".
  - `;;` above a `def` or `data` documents and publishes it, and `;;;`
    describes a file. 23 prelude, 18 io, and 14 test definitions are public;
    helpers such as `read_line_onto` and `length_onto` stay internal.
  - `l0 doc` is an awk program in the driver, since only `tools/l0` is
    installed. Signatures come from the source, so they cannot disagree with
    the types. The index is 119 lines.
  - `l0 spec` reads `spec/L0.md` in a checkout and the installed copy
    elsewhere; `l0 examples` prints `examples.l0` or `examples_test.l0`, and
    `--path` names both, so `l0 test $(l0 examples --path)` runs them.
  - Writing the comments found `rand_bytes` taking a frame per byte, fixed,
    and `rand_below` reaching only about 2 to the 31, now documented.
  - `tests/compiler/examples_check.in` was a copy of three library files that
    had drifted from them already; it is replaced by `examples_check.cat`,
    which `tools/test.sh` concatenates from the working tree.
  - `tests/io/libdoc` pins the index in `libdoc/index.txt`, checks each
    lookup, that an internal name is never shown, `l0 spec`, the examples'
    tests, and that `l0 init` copies exactly two files. Changing one word of
    a doc comment fails it. Both suites green (58 and 68), and on Linux,
    where `awk` is `mawk`.
