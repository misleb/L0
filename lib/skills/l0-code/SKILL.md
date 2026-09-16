---
name: l0-code
description: Read, write, and edit L0 source code (.l0 files). Covers L0 syntax, the standard library, the idioms that keep generated output linear rather than quadratic, and the mandatory l0 check validation loop. Use whenever creating or modifying .l0 files, reading L0 code, or diagnosing L0 type errors.
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
definition errors.

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

Linked automatically. Read `l0/prelude.l0` for the full list; the ones you
will reach for constantly:

- `rev`, `push`, `append`, `length`, `list_eq`, `drop_n`
- `digits` — an int as decimal bytes, which is the only way to print a number
- `starts_with`, `take_line`, `drop_line`, `split_spaces`, `any_eq`, `index_of`
- `is_space`, `is_digit`, `is_lower`, `is_upper`, `hex_val`

There is no `map`, `filter`, or `fold`, because L0 has no function values.
Write the recursion directly.

## The shape of a program

A program defines `main`, which receives stdin as a list of bytes:

```
(def main ((input (list int))) (list int)
  (rev (push "hello\n" (nil int))))
```

The return type may be `(list int)` for raw bytes, or `int` or `bool`, which
are printed as a decimal or as `true`/`false`. There is no other I/O: no
files, no arguments, no clock, no network. A program is a pure function from
bytes to bytes.

## Testing

L0 has no test framework. The convention that works well is one character per
assertion, `y` for pass and `n` for fail, so a diff points at exactly which
assertion broke:

```
(def yn ((ok bool) (rest (list int))) (list int)
  (cons (if ok 121 110) rest))

(def main ((input (list int))) (list int)
  (yn (eq (add 2 3) 5)
  (yn (eq (mul 6 7) 42)
  "\n")))
```

`yn` conses, so nesting inward yields the assertions in source order. Run it
with `l0 run tests.l0` and confirm the output is all `y`.
