---
name: l0-code
description: Read, write, and edit L0 source code (.l0 files) in this repository. Covers L0 syntax, the idioms that keep generated output linear rather than quadratic, and the mandatory l0check validation loop. Use whenever creating or modifying .l0 files, reading L0 code, or diagnosing L0 type errors.
---

# Writing L0

L0 is a language invented in this repository. **There is no L0 in your training
data.** Anything you recall about Lisp, Scheme, Clojure, ML, or Haskell is
either wrong here or accidentally right. Two rules follow from that, and they
matter more than everything else in this file:

1. **[spec/L0.md](../../../spec/L0.md) is the only source of truth.** If a
   construct is not in the spec, it does not exist. Do not infer syntax from
   other languages.
2. **Never claim L0 code works until `tools/l0check` passes on it.** You cannot
   pattern-match your way to correct L0. The checker is your only reliable
   signal.

Read the spec before writing L0 for the first time in a session. It is short.

## The validation loop

```bash
tools/l0check FILE.l0 [MORE.l0 ...]
```

All files given are checked together as one program, because L0 has no module
system. A file that is only part of a program will report unknown names unless
its companions are listed too.

Diagnostics are `file:line:column: error: message` and the checker reports one
error per declaration, so a single run finds many problems at once. Fix them,
re-run, and only proceed at zero errors.

To run a program:

```bash
build/l0i run FILE.l0 [MORE.l0 ...] < input-bytes
```

Then `tools/test.sh` before considering any change done.

## Syntax you will get wrong if you guess

These are the places where L0 differs from what a Lisp-shaped language leads
you to expect. Every one of them is a real error the checker will catch, but
knowing them saves a round trip.

**`nil` takes its element type.** There is no bare `(nil)` and no inference.

```
(nil int)           (nil Token)           (nil (list int))
```

**Types are parenthesized.** A list type is `(list int)`, never bare `list`.

```
(def f ((xs (list int))) (list int) xs)
```

**Case is meaningful.** Functions, parameters, and bindings start lowercase or
with `_`. Types and constructors start uppercase. This is how the reader tells
a constructor from a variable, so it is not a style preference.

**`let` binds exactly one name and has a body.** It is not `let*`, and there is
no binding list. Sequential bindings are nested lets.

```
(let a 1
  (let b (add a 1)
    (add a b)))
```

**Every `match` arm is `((Ctor names...) result)`,** with one name per field,
patterns one level deep, every constructor present exactly once, and **no
wildcard or default arm**. Nullary constructors keep their parentheses.

```
(match tok
  ((TInt n)  n)
  ((TName s) (length s))
  ((TEnd)    0))
```

**Nullary constructors are called with parentheses** in expressions too: `(Red)`,
not `Red`.

**There are no function values.** You cannot pass, return, or bind a function,
and there are no closures or higher-order functions. Recursion replaces both
loops and iteration combinators.

**`and` and `or` are strict.** Both arguments are always evaluated, so they do
not guard against errors. This does not work:

```
(and (not (is_empty xs)) (gt (head xs) 0))   ; still calls head on empty
```

Use nested `if` instead:

```
(if (is_empty xs) false (gt (head xs) 0))
```

**`eq` compares integers only.** Comparing lists or data values needs a function
written in L0; see `list_eq` in
[tests/lib/assert.l0](../../../tests/lib/assert.l0).

**A name in call position is never a local.** `(f 1)` always means a builtin or
a `def`, so a parameter named `f` cannot be called and does not shadow a
function named `f`. See spec section 7.

**`read_byte` and `write_byte` are effects, sequenced by `let`.** Effects happen
in evaluation order, and a `let` value is evaluated before its body even when
its name is unused, so `(let w (write_byte 63) (read_byte))` writes, then reads.
A `main` that uses them usually takes no parameters and returns the exit
status; see spec sections 6.2 and 9. **The compiler's own sources must not use
them**, and nor may `lib/prelude.l0`: stage 0 runs both and does not know
them. Line helpers belong in `lib/io.l0`, and tests in `tests/io/`. The same
goes for the file and argument builtins of spec sections 6.3 and 6.4. When
`lib/io.l0` is among the files given to `tools/l0check` or `tools/l0c`, it and
`lib/prelude.l0` are checked as the prelude group, since only the prelude may
declare the `Io` names spec section 7.1 reserves.

## The one performance rule

**Build output as a reversed accumulator and reverse once at the end.**

Appending to the end of a list copies the whole list, so building output with
repeated appends is quadratic in the size of the output. Code written that way
passes every small test and then appears to hang forever on real input. This is
the most likely way to waste a day on this project.

The idiom, which every output-producing function should use:

```
(def push ((chunk (list int)) (acc (list int))) (list int)
  (if (is_empty chunk)
      acc
      (push (tail chunk) (cons (head chunk) acc))))
```

`push` costs the length of the chunk, not the length of the accumulator, so
total cost stays linear. Chunks go on in order and the accumulator ends up
backwards, so one `rev` at the very end puts it right:

```
(def render ((n int)) (list int)
  (let a (push "count=" (nil int))
    (let b (push (digits n) a)
      (rev (push "\n" b)))))
```

Never call `rev` in a loop or per chunk. Exactly once, at the end.

## Keep nesting shallow, or you will miscount parentheses

This is the most common way to waste time writing L0, and it was the cause of
every parse error hit while writing the compiler. A chain of six `if`s or ten
`or`s ends in a run of a dozen `)`, and getting that run wrong is easy and the
resulting error points at the start of the form rather than the mistake.

Three fixes, in order of preference:

**Test membership with a word table instead of an `or` chain.** `split_spaces`
and `any_eq` in [lib/prelude.l0](../../../lib/prelude.l0) turn a
ten-deep nest into one flat line:

```
(def is_reserved ((n (list int))) bool
  (any_eq n (split_spaces "def data if let match nil true false int bool list")))
```

`index_of` does the same for dispatch tables, mapping a name to a position so
two parallel tables can be indexed together.

**Collapse a `match` to a predicate.** `match` has no wildcard, so inspecting
a six-constructor type inline costs six lines every time. Write the match once
as a `kind` function returning an int, then build predicates on it; see
`tok_kind` and `tok_is_lparen` in [compiler/lex.l0](../../../compiler/lex.l0).

**Split the function.** A function whose body nests more than about four
levels should hand the tail off to a helper. `check_if` and `check_if_branches`
in [compiler/check.l0](../../../compiler/check.l0) are one expression split at
the point where nesting got out of hand, and both are readable as a result.

## Idioms worth copying

Accumulator-passing for iteration, since there are no loops:

```
(def sum_onto ((xs (list int)) (acc int)) int
  (if (is_empty xs) acc (sum_onto (tail xs) (add acc (head xs)))))
```

Prefer this tail-recursive shape over the non-tail version when the list may be
long. A tail call uses no stack, whatever the arities and optimization level
(spec section 8), while the non-tail version holds one stack frame per element.
The runtime's stack is 512 MB by default, and `L0_STACK_MB` changes it, so deep
non-tail recursion works too, but only tail calls are unbounded.

Decimal formatting, which L0 has no builtin for, is in
[tests/lib/assert.l0](../../../tests/lib/assert.l0) as `digits`. Copy it rather
than rewriting it.

## Reading existing L0

Working examples worth reading before writing anything substantial:

- [tests/lib/assert.l0](../../../tests/lib/assert.l0) — `rev`, `push`, `digits`,
  `list_eq`, `length`
- [tests/lang/data.l0](../../../tests/lang/data.l0) — data types, `match`,
  recursive and mutually recursive types, lists of data values
- [tests/lang/bindings.l0](../../../tests/lang/bindings.l0) — `let`, shadowing,
  and the namespace separation

## Writing the standard library

`lib/prelude.l0`, `lib/io.l0`, and `lib/test.l0` document themselves, and
`l0 doc` is how every agent outside this repository learns what they offer,
so their documentation is part of the change, not an afterthought:

- a `;;` block directly above a `def` or `data` is its documentation, and
  makes it public. Its first sentence is the one-line summary `l0 doc` shows,
  so make that sentence say what the function returns or does, including how
  it fails
- a definition without a `;;` block is internal and never listed, which is
  right for helpers such as `read_line_onto`
- `;;;` lines describe the whole file, and their first sentence heads the
  file in the index
- `tests/io/libdoc` pins the whole index in `tests/io/libdoc/index.txt`.
  Adding, removing, or re-documenting a public definition changes it; update
  it with `tools/l0 doc > tests/io/libdoc/index.txt` and read the diff

## Writing tests

Anything stage 0 cannot run, including library code in `lib/io.l0` and
`lib/test.l0` and programs a worker writes, is tested with `tools/l0 test`,
which `lib/skills/l0-code/SKILL.md` describes. That skill is written for a
project `l0 init` made, where `l0` is on the path; here it is `tools/l0`, and
`tools/l0 doc`, `tools/l0 spec`, and `tools/l0 examples` read `lib/` and
`spec/` as they are in the working tree. Check a test file with
`tools/l0 check --test`, or with `tools/l0check` given `lib/test.l0`, which
both group it as `l0 test` does. Such tests live in
`tests/unit/NAME_test.l0`, with a `.extra` file naming companions if needed,
and `tools/test.sh --compiled` runs each through `l0 test` in a scratch
directory, against the compiler it just built. `tests/io/` is only for what a
test function cannot check: the two forms of `main`, exit status, standard
input, arguments, and timing. `tests/io/framework.sh` tests `l0 test` itself. What follows is the convention for `tests/lang/`, which stays
as it is because stage 0, the oracle, cannot run `l0 test`'s I/O.

Tests in `tests/lang/` return one character per assertion, `y` for pass
and `n` for fail, so a diff points at the exact assertion that broke instead of
at an aggregate number. `yn` conses, so nesting inward yields source order:

```
(def main ((input (list int))) (list int)
  (yn (eq (add 2 3) 5)
  (yn (eq (mul 6 7) 42)
  "\n")))
```

Add `tests/lang/NAME.extra` containing `tests/lib/assert.l0` to get the helpers,
then `tools/test.sh --bless NAME`, then **read the generated `.out` file** and
confirm it is all `y`. Blessing without reading the result defeats the purpose.

For the full expectation-file layout, see the comment block at the top of
[tools/test.sh](../../../tools/test.sh).
