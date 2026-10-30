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

Read the spec before writing L0 for the first time in a session: sections 1
to 9 are the language a program is written in, and section 10, the larger
half, is the compilation target, the runtime, and the boards, which an
ordinary program does not need.

## The validation loop

```bash
tools/l0check FILE.l0 [MORE.l0 ...]
```

All files given are checked together as one program, because L0 has no module
system. A file that is only part of a program will report unknown names unless
its companions are listed too. `tools/l0check` checks only the files given,
so a program that uses the library lists `lib/prelude.l0 lib/io.l0` first,
which then become the prelude group; `tools/l0 check` adds them itself, but
compiles with the seed (the `l0-bootstrap` skill says when that matters).

Diagnostics are `file:line:column: error: message` and the checker reports one
error per declaration, so a single run finds many problems at once. A
declaration that does not parse is reported once, and its uses are not
reported as unknown, so fixing it can reveal errors that were hidden. Fix
them, re-run, and only proceed at zero errors.

To run a program, with the standard library linked:

```bash
tools/l0 run FILE.l0 [MORE.l0 ...] [-- ARGS] < input-bytes
```

Not `build/l0i run`: the frozen stage-0 interpreter knows nothing added
since, so it rejects type parameters, `eq` on anything but `int`, `hash`,
`compare`, the I/O, file, and argument builtins (`remove` and `read_some`
among them), arrays, bytes, the clock, the bit builtins, and floats.

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

**`let` binds one name, or several in pairs, and has a body.** Sequential
bindings are nested lets, which `(let (a 1 b (add a 1)) body)` writes in one
form (spec 5.3), each value seeing the names before it; and `(if c1 e1 c2
e2 else)` is the nested `if` chain (spec 5.2). Both are desugared by the
parser, so stage 0 cannot run them: tests of them are `tests/unit/sugar_test`
and `tests/compiler/check_sugar`.

```
(let a 1
  (let b (add a 1)
    (add a b)))

(let (a 1 b (add a 1))
  (add a b))
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

**A constructor may name its fields, and a field is read or replaced by
name** (spec 4 and 5.8): `(data Proc (Proc (space int) (state int)))`, then
`(.state p)` and `(.state p -1)`. All of a constructor's fields are named
or none, only a one-constructor type has fields read this way, and
construction and `match` stay positional. The compiler's `Ctx`, `Emit`,
and `Env` are written so; a field name is a token of its own, so `.state`
cannot collide with a function or binding named `state`. Stage 0 predates
fields, so tests of them go in `tests/unit/` or `tests/io/`, or in
`tests/compiler/check_fields` for the checker's verdicts.

**A function is passed by name, never kept** (spec 5.7). A parameter of type
`(fn (T) K)` is given a `def` by name, or a function parameter passed on,
and is called like a function; it cannot be returned, bound, or stored, a
builtin cannot be passed, and there are no closures. Each `def` passed makes
a copy of the callee (spec 10.2), so every call stays direct. Stage 0
predates this, so tests of it go in `tests/unit/fn_args_test.l0`, or in
`tests/compiler/check_fn_args` for the checker's verdicts and
`emit_fn_args` for the copies.

**`and` and `or` stop at the first operand that decides** (spec 8), so
`(and (not (is_empty xs)) (gt (head xs) 0))` never takes the head of an
empty list. Stage 0 predates this and keeps the strict reading, so a test of
it goes in `tests/io/and_or_short` or `tests/unit`, never `tests/lang`. The
second operand is not in tail position, so a loop through it is written
with `if`.

**`eq` compares two values of any one type** (spec 6.8), lists, data, arrays,
and bytes by what they hold, but stage 0 predates that and accepts only `int`.
So anything in `tests/lang/` compares lists with a function such as `list_eq`
in [tests/lib/assert.l0](../../../tests/lib/assert.l0), and `eq` on anything
else is tested in `tests/unit/` or `tests/io/`. The compiler's sources and
`lib/prelude.l0` may use it, since stage 0 never runs them and the seed
compiles it. `lt`, `le`, `gt`, and `ge` take only `int` everywhere. `hash`
(spec 6.9) is the same: any type, unknown to stage 0, tested in
`tests/unit/hash_test.l0` against values computed from the spec alone. So is
`compare` (spec 6.11), which orders any type, tested in
`tests/unit/compare_test.l0`. The seed knows it, and the prelude's `sort`,
`min`, and `max` use it.

**A name in call position is a local only when it is a function parameter.**
`(f 1)` means a parameter of function type named `f`, when the innermost
local `f` is one, and otherwise a `def` or a builtin, so a parameter of any
other type named `f` cannot be called and does not shadow a function named
`f`. See spec section 7.

**`read_byte` and `write_byte` are effects, sequenced by `let`.** Effects happen
in evaluation order, and a `let` value is evaluated before its body even when
its name is unused, so `(let w (write_byte 63) (read_byte))` writes, then reads.
A `main` that uses them usually takes no parameters and returns the exit
status; see spec sections 6.2 and 9. Line helpers belong in `lib/io.l0`, not
`lib/prelude.l0`, which the compiler links and which needs no I/O, and tests
of them in `tests/io/`, since stage 0 does not know them. The same goes for
the file and argument builtins of spec sections 6.3 and 6.4. When
`lib/io.l0` is among the files given to `tools/l0check` or `tools/l0c`, it and
`lib/prelude.l0` are checked as the prelude group, since a program's
functions, types, and constructors shadow the prelude's (spec section 7.1).
Opening a file gives an `(IoOpened OpenFault)` or `(IoOpened CreateFault)`,
whose `((IoFailed fault why) ...)` arm has the failure as a case and as
words: test the case with `eq`, as `kvlog`'s `kv_load` does with `(eq fault
(OpenMissing))`, never the words. Renaming, removing, flushing, and closing
give an `(IoDone E)`, with a `RenameFault`, `RemoveFault`, or `WriteFault`
in its `((NotDone fault why) ...)` arm, tested the same way.
`tests/io/open_faults` shows each case of opening and renaming,
`tests/io/remove` each of removing, and `tests/unit/io_test.l0` compares
whole `IoDone` values with `eq`.

**Type parameters have the same limit in tests.** `(data (Option T) ...)`,
`(Option int)`, `((None int))`, and `(def (rev T) ...)` are L0 (spec 4, 4.1,
and 5.6), but stage 0 predates them, so tests of them go in `tests/io/` or
`tests/unit/` or, for the checker's verdicts, in a `tests/compiler/` stage
test such as `check_params` or `check_fn_params`, which gives the source to
the checker as data. The compiler's sources and `lib/prelude.l0` may use
them, as they may use anything the seed compiles: the tools build the
compiler with the seed (`tools/compiler.sh`), and stage 0 runs only the
programs in `tests/lang/` and `tests/check/`. The same holds for a program
that shadows a
prelude type or constructor (spec 7.1): stage 0 still resolves upper names
across both groups, so see `tests/io/shadow_types` and
`tests/compiler/groups`.

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

## The hidden whole copy

The second way to go quadratic unseen. `map_put`, `map_remove`, `array_set`,
and a field replacement `(.f r v)` update in place only when nothing else
still holds the map, array, or record, and otherwise copy it whole first
(spec section 6.5), with the same results. Two shapes do it with no second
name in sight, and a worker hit both in one session:

```
(Seen (map_put m k true) (if (map_has m k) n (add n 1)))   ; copies m: read after the put
(let fresh (not (map_has m k))                             ; right: read, then put
  (Seen (map_put m k true) (if fresh (add n 1) n)))

(let t (space_put s page frame)                            ; copies s's map: s used after
  (Mapped t (digits (space_number s))))
(let id (space_number s)                                   ; right: read s first
  (Mapped (space_put s page frame) (digits id)))
```

A read inside the update's own call, as in `(map_put m k (map_size m))` or
`(.n r (add (.n r) 1))`, is fine, since an operand that is the variable
itself is taken last (10.3); `(.n (.m r 1) (.m r))` copies `r`, since the
outer form reads it after the inner replacement. A field holding an array
or map, updated through a function and put back as `(.ctx p (call_result
(.ctx p) v))`, is taken out for the function and updates in place (spec
6.5's field form, `tests/io/fields_in_place`'s `through` mode), unless `p`
is used again after.
`tests/io/fields_in_place` measures both shapes.
`L0_ARRAY_STATS=1` on a run reports how many updates copied; maps count, as
arrays. `lib/examples.l0`'s `see_key` and `map_logged` are the fixes, and
`lib/skills/l0-code/SKILL.md` has the trap in full.

## Keep nesting shallow, or you will miscount parentheses

This is the most common way to waste time writing L0, and it was the cause of
every parse error hit while writing the compiler. A chain of six `if`s or ten
`or`s ends in a run of a dozen `)`, and getting that run wrong is easy.

**Let `tools/l0 fmt` count the ones at the end.** Indent each line under
its parent form and run `tools/l0 fmt FILE.l0` before `tools/l0check`:
where a line dedents below the line a form began on, and at the next
declaration at column 0, it adds the closers still missing at the end of
the line before, drops closers with nothing to close, and changes nothing
else, so a file that is already right comes back byte-identical
(`tests/io/fmt` holds the compiler, the library, and the kernel to that).
It keeps every closer written, since L0's flat `if` chains, match arms,
hanging `append` chains, and operands aligned under a form's `(` all look
like a missing closer to a stricter rule (`tools/fmt.l0`'s header lists
them). `tools/l0 fmt --check` only reports. When a count is still off, the
checker says by how many and at which line it probably went wrong
(`tests/check/parens_*`).

Three more fixes, in order of preference:

**Test membership with a word table instead of an `or` chain.** `split_spaces`
in [lib/prelude.l0](../../../lib/prelude.l0) and `any_eq` turn a ten-deep nest
into one flat line. `any_eq` and `index_of` are generic, and in the prelude
too, so the compiler calls the same ones a program does:

```
(def is_reserved ((n (list int))) bool
  (any_eq n (split_spaces "def data if let match nil true false int bool list")))
```

`index_of` does the same for dispatch tables, mapping a name to a position so
two parallel tables can be indexed together. For a table that is looked up
often or grows, such as a symbol table or counts by word, use the prelude's
`(Map K V)` (`tools/l0 doc Map`) rather than a list of pairs or a trie of your
own: any type can be a key, the empty map is written `((MapEmpty K V))`,
and it changes in place while nothing else holds it. The compiler keeps its
pad table in one (`pad_map` in [compiler/emit.l0](../../../compiler/emit.l0)),
and `tests/unit/map_test.l0` tests it.

**Collapse a `match` to a predicate.** `match` has no wildcard, so inspecting
a six-constructor type inline costs six lines every time. Write the match once
as a `kind` function returning an int, then build predicates on it; see
`tok_kind` and `tok_is_lparen` in [compiler/lex.l0](../../../compiler/lex.l0).

**Name the fields of a one-constructor type** instead of writing a function
per field: `(.sigs c)` reads and `(.tparams c fps)` replaces, with no
`match` and no nesting. `Ctx` in [compiler/check.l0](../../../compiler/check.l0)
and `Kern` in `tests/virt/user/kernel.l0` are written so.

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

Number formatting, which L0 has no builtin for, is the prelude's `digits` and
`hex_digits`; use them. Only a `tests/lang` program, which stage 0 runs
without the library, gets `digits` from
[tests/lib/assert.l0](../../../tests/lib/assert.l0) through its `.extra`.

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
input, arguments, and timing; files and directories a `.sh` sets up, such as
a directory or a file that may not be read (`remove`, `open_faults`); broken
pipes and closed standard handles (`broken_pipe`, `closed_std`); runtime
failures, with the expected standard error and exit status in `.err` and
`.exit` (`array_range`); and the generated IR or a build at `-O0`
(`eq_read_only`, `tail_calls`, `prelude_depth`). `tests/io/framework.sh`
tests `l0 test` itself. What follows is the convention for `tests/lang/`, which stays
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
