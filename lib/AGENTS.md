# Working with L0 in this project

L0 is a statically typed language compiled to native code through LLVM.
**There is almost certainly no L0 in your training data**, so familiarity
cannot substitute for reading the specification and running the checker.

## Invariants

**The specification is the only source of truth about L0.** Not this file, not
the examples. If a construct is not in it, it does not exist. `l0 spec --path`
names the file; read it before writing L0 for the first time in a session.

**Never state that L0 code works without running `l0 check` on it.** Code that
looks plausible is routinely invalid, because L0 is not any language you have
seen. That it type checks says nothing about what it does: write tests, and
run them with `l0 test`.

**Every program is three files, and is not done until its tests pass.** This
holds for hello world too:

```
hello.l0        what the program does, as functions
hello_test.l0   tests of them: (def test_NAME () int ...), run by l0 test
main.l0         only main, which calls into hello.l0 and returns the status
```

`l0 test` supplies its own `main`, so code inside `main` cannot be tested;
keep `main.l0` to input, one call, and the exit status. Done means
`l0 test hello.l0 hello_test.l0` passes and `l0 build hello.l0 main.l0`
builds. The `l0-code` skill has hello world written out this way.

**Run `l0 doc` before writing a helper.** It lists every function and type in
the standard library, which is linked into every program, and `l0 doc NAME`
shows one in full. What you would have written may already be there.

**Read the examples before writing anything substantial.** `l0 examples
--path` names two files: working programs covering recursion, strings, data
types, `match`, returning several values, reporting failure, arrays, and
bytes, and tests of them.

Everything these commands show comes from the installed toolchain, so it
always describes the compiler that builds this project. Nothing of it is
copied here.

## Commands

```bash
l0 check hello.l0 main.l0         type check
l0 test  hello.l0 hello_test.l0   run every (def test_NAME () int ...), as TAP
l0 run   hello.l0 main.l0         build and run, reading stdin; -- ARGS after
l0 build hello.l0 main.l0         produce the executable ./hello
l0 doc   [NAME | TEXT]            the standard library, or one name, or a search
l0 spec  --path                   where the specification is
```

Several files are compiled together, since L0 has no module system. The
standard library is linked automatically, and `l0 test` adds its assertions,
so never pass library files on the command line.

**A function you define shadows a prelude function or builtin of the same
name**, and the prelude keeps calling the original, so a name L0 or the
standard library already took is never something you have to work around.
A type or constructor you declare shadows the library's of the same name in
the same way.

## When L0 cannot express something

**The L0 toolchain is read-only here.** Never edit the installed prelude or
compiler, and never vendor a patched copy. L0 is changed in its own
repository, not from projects that use it.

If L0 cannot express what was asked, say so plainly and name what could not be
written. Do not ship something that quietly narrows the task: a program that
does something adjacent to what was asked, with tests written from the same
narrowed contract, passes and is still wrong.

Anything a ten-line function solves is not a language limitation. A prompt, a
confirmation, or progress during a run is not one either: write it with a
`main` that takes no parameters and reads and writes as it goes, as the
`l0-code` skill shows, and so are files and command-line arguments. Memory is
reclaimed automatically, and `clock_ns` times part of a program. A network
and the environment do not exist yet.

## Two traps specific to L0

**Quadratic output.** Building output by appending is quadratic; it passes
every small test and then appears to hang on real input. Accumulate with
`push` onto a reversed list and call `rev` exactly once at the end.

**Deep nesting and parentheses.** Long `if` and `or` chains end in a dozen
closing parens and are the most common source of parse errors. Use
`split_spaces` with `any_eq` for membership tests, and split any function
nesting more than about four levels deep.

The `l0-code` skill covers both in detail, along with the syntax that differs
from what other languages would lead you to expect.
