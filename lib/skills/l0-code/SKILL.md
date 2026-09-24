---
name: l0-code
description: Read, write, and edit L0 source code (.l0 files). Covers L0 syntax, the standard library, the idioms that keep generated output linear rather than quadratic, the mandatory l0 check validation loop, and the testing convention. Use whenever creating or modifying .l0 files, reading L0 code, diagnosing L0 type errors, or writing tests. Also use when a shipped skill is wrong or incomplete and the improvement should go back to L0.
---

# Writing L0

L0 is a small, pure, statically typed language. **There is almost certainly no
L0 in your training data.** Anything you recall about Lisp, Scheme, Clojure,
ML, or Haskell is either wrong here or accidentally right. Two rules follow,
and they matter more than everything else in this file:

1. **`l0/L0.md` is the only source of truth.** If a construct is not in the
   specification, it does not exist. Do not infer syntax from other languages.
2. **Never claim L0 code works until `l0 check` passes on it.** You cannot
   pattern-match your way to correct L0. The checker is your only reliable
   signal.

Read `l0/L0.md` before writing L0 for the first time in a session. It is
short. Then skim `l0/examples.l0`, which is a set of working programs.

## The loop

```bash
l0 check prog.l0          # type check; prints ok, or diagnostics
l0 run   prog.l0 < input  # build and run, reading stdin
l0 build prog.l0 -o prog  # produce an executable
```

Diagnostics are `file:line:column: error: message`. Several files are compiled
together, because L0 has no module system:

```bash
l0 check util.l0 main.l0
```

The standard library is linked automatically. `l0/prelude.l0` is a readable
copy of it; do not pass it on the command line or you will get duplicate
definition errors. Defining a function with the same name as one of its
functions is fine, and is not what that error is about.

## Syntax you will get wrong if you guess

**`nil` takes its element type.** There is no bare `(nil)` and no inference.

```
(nil int)           (nil Token)           (nil (list int))
```

**Types are parenthesised.** A list type is `(list int)`, never bare `list`.

**Case is meaningful.** Functions, parameters, and bindings start lowercase or
with `_`. Types and constructors start uppercase. This is how the reader tells
a constructor from a variable, so it is not a style preference.

**`let` binds exactly one name and has a body.** It is not `let*`, and there
is no binding list. Sequential bindings are nested lets.

```
(let a 1
  (let b (add a 1)
    (add a b)))
```

**Every `match` arm is `((Ctor names...) result)`,** one name per field,
patterns one level deep, every constructor present exactly once, and **no
wildcard or default arm**. Nullary constructors keep their parentheses, in
patterns and in expressions: `(Red)`, never `Red`.

**There are no function values, closures, or higher-order functions.**
Recursion replaces both loops and iteration combinators.

**There are no tuples.** A function returning two things declares a small
`data` type; see `Split` in `l0/examples.l0`.

**There are no exceptions.** A function that can fail returns a `data` type
with a case per outcome; see `Parsed` in `l0/examples.l0`.

**`and` and `or` are strict.** Both arguments are always evaluated, so they do
not guard against errors. This still calls `head` on an empty list:

```
(and (not (is_empty xs)) (gt (head xs) 0))   ; wrong
(if (is_empty xs) false (gt (head xs) 0))    ; right
```

**`eq` compares integers only.** Comparing lists uses `list_eq` from the
standard library; comparing data values needs a function you write.

**A name in call position is never a local.** `(f 1)` always means a builtin
or a `def`, so a parameter named `f` cannot be called and does not shadow a
function named `f`.

**Your definition wins over the standard library's.** Defining `length` when
the prelude already has one is legal rather than a collision: yours is used
everywhere in your program, and the prelude goes on calling its own, so
redefining something the prelude uses internally cannot break it. Type and
constructor names are not shadowable and still have to be unique. Spec
section 7.1.

## The one performance rule

**Build output as a reversed accumulator and reverse once at the end.**

Appending to the end of a list copies the whole list, so building output with
repeated appends is quadratic in the size of the output. Code written that way
passes every small test and then appears to hang on real input.

```
(def render ((n int)) (list int)
  (let a (push "count=" (nil int))
    (let b (push (digits n) a)
      (rev (push "\n" b)))))
```

`push` costs the length of the chunk, not the length of the accumulator. Call
`rev` exactly once, at the very end, never per chunk. Use `append` only for
short strings such as diagnostics.

## Keep nesting shallow, or you will miscount parentheses

This is the most common way to waste time writing L0. A chain of six `if`s or
ten `or`s ends in a run of a dozen `)`, and the resulting error points at the
start of the form rather than at the mistake.

**Test membership with a word table** instead of an `or` chain:

```
(def is_keyword ((n (list int))) bool
  (any_eq n (split_spaces "def data if let match nil true false")))
```

**Collapse a `match` to a predicate.** Since `match` has no wildcard,
inspecting a six-constructor type inline costs six lines every time. Write the
match once as a function returning an int, then build predicates on it.

**Split the function.** A body nesting more than about four levels should hand
its tail to a helper.

## The standard library

Linked automatically. Read `l0/prelude.l0` and `l0/io.l0` for the full list;
the ones you will reach for constantly:

- `rev`, `push`, `append`, `length`, `list_eq`, `drop_n`
- `digits` — an int as decimal bytes, which is the only way to print a number
- `starts_with`, `take_line`, `drop_line`, `split_spaces`, `any_eq`, `index_of`
- `is_space`, `is_digit`, `is_lower`, `is_upper`, `hex_val`

There is no `map`, `filter`, or `fold`, because L0 has no function values.
Write the recursion directly.

If one of these does not do what you need, define your own with the same name
rather than inventing `my_length`. Yours shadows the prelude's throughout your
program and cannot disturb the prelude's own use of it.

## The shape of a program

A program defines `main` in one of two forms. The first receives stdin as a
list of bytes and returns its output:

```
(def main ((input (list int))) (list int)
  (rev (push "hello\n" (nil int))))
```

The return type may be `(list int)` for raw bytes, or `int` or `bool`, which
are printed as a decimal or as `true`/`false`. Nothing is written until `main`
returns, and all of stdin is read before it starts.

The second takes nothing, reads and writes as it goes, and returns the exit
status. Use it when a program must write before its input ends, such as a
prompt, or must not hold its whole input at once:

```
(def main () int
  (let w (write_str "What is your name? ")
    (let name (take_line (read_line))
      (let g (write_str (append "Hello, " (append name "!\n")))
        0))))
```

`read_byte` and `write_byte` are the builtins; `read_line`, `write_str`, and
`write_line` are in `l0/io.l0`. They are effects, and **effects happen in
evaluation order**, so nest `let`s to put one before another. A `let` whose
name you never use is still evaluated, which is exactly what makes it the way
to sequence. `read_line` returns the empty list only at end of input, and
keeps the line's newline, so strip it with `take_line`.

Output written before a read that has to wait is always shown first, so a
prompt appears before the program waits for its answer.

**Files and arguments.** Use the `l0/io.l0` wrappers, not the raw builtins.
`(open_in path)` and `(open_out path)` return `IoOpened`, and `match` makes you
handle its `IoFailed` case, whose field says why in words. Then
`file_read_byte`, `file_read_line`, `file_write_str`, and `file_close` work on
the `IoFile` inside. `(arg_count)` and `(arg i)` are the command-line
arguments, not counting the program's name. `write_err` writes to standard
error. Report failure by returning a nonzero exit status from `main`.

A file read returns -1 at end of input and another negative number if the
read failed, so test for -1 and for other negatives separately, or a failed
read looks like a short file. `file_close` on a file you wrote returns a
negative number if its bytes could not be written, which is the only place a
write failure shows up; check it.

Type and constructor names beginning with `Io` and an uppercase letter, such
as `IoFile`, are reserved for the standard library, so name your own types
something else.

**Memory is reclaimed by reference counting**, with nothing for you to do, but
how you write a program decides how much it holds. A value is freed when the
scope that bound it ends, not at its last use, and a loop in tail position
frees each iteration's garbage before the next. So:

- to process a large input, use the streaming `main` and read it a line or a
  byte at a time; that runs in constant memory however long the input is
- a `main` that takes its input gets it as a list built in full before `main`
  starts, one cons cell per byte, about 2.4 GB for 100 MB, however little of
  it `main` then keeps
- write loops as tail calls, so each iteration's values are freed as it goes

There is no clock, network, or environment yet.

## Testing

Use `l0 test`. `l0/examples_test.l0` is a worked file of tests; read it first.

```bash
l0 test lib_code.l0 lib_code_test.l0             # every test, as TAP
l0 test lib_code.l0 lib_code_test.l0 --match parse   # only names containing "parse"
```

A test is `(def test_NAME () int ...)`, with its name and `()` on the line it
starts. There is no list of tests to maintain: `l0 test` finds them, builds
the files once with `l0/test.l0` linked, and runs each test in its own
process. It prints `ok N - test_NAME` or `not ok N - test_NAME` with what went
wrong underneath, and exits nonzero if any failed.

A test returns how many of its assertions failed. Sum several with `add`,
which runs them in order:

```
(def test_parse_digits () int
  (add (check_int "value" (parse_or_zero "42") 42)
       (check_str "rest" (first_line "a\nb") "a")))
```

The assertions are `check_int`, `check_bool`, `check_true`, `check_str`, and
`check_strs`, each taking a name, what the code computed, and what it should
be. A failing string is shown as an L0 literal you can paste back, with the
first byte where it differs. For a data type, `match` on it inside the test
and name the case that should not happen.

**Keep each test to one to three assertions, and write many tests.** Long
chains of nested assertions are where closing parentheses get miscounted.

**A runtime error fails only its own test**, and its message is shown. To test
that code must fail, give the test an `expect_NAME` with the same NAME:

```
(def test_empty_head () int (head (nil int)))
(def expect_empty_head () (list int) "head of empty list")
```

**Golden files** hold expected output too long to write inline:
`(check_file "name" got "path/to/expected.txt")`, with the path relative to
where `l0 test` runs. `l0 test --bless` writes the files instead of comparing,
and lists each one it wrote. Blessing turns whatever the code does now into
what is correct, so read the diff of every file it touched.

**Property tests** use `rand_next` and `rand_below` from `l0/test.l0`, which
give the same sequence on every run, so a failure reproduces. Check a
property over a few hundred inputs, such as two implementations agreeing, or
parsing what was printed.

Test files do not define `main`, since `l0 test` supplies one, and a test that
uses `arg` sees `l0 test`'s arguments, not yours. Test a whole program by
putting its logic in functions and testing those, or by running it with
`l0 run` and comparing what it writes.
