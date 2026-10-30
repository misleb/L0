# Adopting L0's new forms and tools in L0S

For the agent integrating L0 into L0S. This guide is kept current: every
roadmap item that changes what a program can write, what the library
offers, or what the tools do adds its section here as it lands, with a
snippet this repository's suite compiles and a grep for where it applies
in L0S, and the roadmap skill's "Done when" requires it. The sections
below are in the order the items landed; the newest is last.

L0 gained, on 2026-10-30, named fields (roadmap 0132), `l0 fmt` (0133), a
`let` of several bindings and an `if` of several tests (0134), a crash fix
in the lexer, and diagnostics that count a declaration's parens. Nothing L0S already compiles stops compiling:
every change adds a form or a tool, no name moved, and the runtime gained
one function, append-only. Every snippet below is copied from a file this
repository's suite compiles and runs, `lib/examples.l0` or
`tests/unit/sugar_test.l0`, so none of it is untested. The counts quoted
for L0S come from the greps shown, run over its `.l0` files on that date.

## 1. Install, and tell that you have it

From this repository, at a commit at or after roadmap 0134:

```bash
tools/install.sh --prefix ~/.local
```

`l0 version` prints only where the library is, so check with a form the
old toolchain rejects and the new one accepts:

```bash
printf '(data P (P (a int)))\n(def main () int (.a (P 1)))\n' > /tmp/has_fields.l0 && l0 check /tmp/has_fields.l0
l0 fmt --check /tmp/has_fields.l0 && echo "l0 fmt is installed"
```

Both say `ok` on the new toolchain; the old one reports `unexpected
character` at the `.` and knows no `fmt` command.

Before changing anything in L0S, run its own checks under the new
toolchain, `l0 check` and `l0 test` over every program: they must pass as
before. Then `l0 fmt --check` over every `.l0` file: it should change
nothing, since L0S's closers match its indentation; where it would, read
the diff, since it has found a count that is off.

## 2. Named fields

A constructor may name its fields, all of them or none, and a field is then
read by name and replaced by name. Construction and `match` stay positional;
only a type with one constructor has fields read this way; a field name is
a token of its own, `.state`, so it never collides with a function or
binding named `state`. Spec 2.4, 4, and 5.8.

```
(data Proc
  (Proc (space int) (ctx (array int)) (state int)))

; p stopped: its state -1, the rest as it was.
(def stop ((p Proc)) Proc
  (.state p -1))

; p's program counter, word 32 of its context.
(def proc_pc ((p Proc)) int
  (array_get (.ctx p) 32))

; Several fields: nest the replacements. After the first, the value is
; held by nothing else, so the rest store in place (spec 6.5).
(def restart ((p Proc) (pc int)) Proc
  (.state (.ctx p (array_set (array_new 104 0) 32 pc)) 0))
```

**Where L0S gains.** The shape to convert is a function whose whole body is
one `match` arm returning one field. This finds them, 429 in L0S:

```bash
grep -rnE '\(match [a-z]+ \(\([A-Z][A-Za-z0-9]*( [a-z][a-z0-9]*)+\) [a-z][a-z0-9]*\)\)\)' --include='*.l0' .
```

For each, name the type's fields in its `data` declaration, delete the
function, and write `(.field value)` at its call sites; the compiler's
`Ctx`, `Env`, and `Emit` were converted this way and its IR shrank by 22 KB.
The other shape is a constructor applied to its own match bindings with one
changed, `(match p ((Proc s c m w st) (Proc s c m w -1)))`, which becomes
`(.state p -1)`; this approximates it:

```bash
grep -rnE '\(match [a-z]+ \(\(([A-Z][A-Za-z0-9]*) [a-z0-9 ]+\) \(\1 ' --include='*.l0' .
```

**What not to convert.** A `match` that takes several fields at once, which
is cheaper than several reads. A type with several constructors, which
keeps `match`. And, above all, a field that holds an array or a map and is
updated and put back:

```
; The map inside is updated and put back, so it is taken out by a match,
; which releases s once it has the fields: written (.pages s (map_put
; (.pages s) page frame)), the read would hold the map while s does too,
; and map_put would copy it.
(def space_put ((s Space) (page int) (frame int)) Space
  (match s ((Space id pages) (Space id (map_put pages page frame)))))
```

That is the field case of the hidden whole copy: `(.ctx p (call_result
(.ctx p) v))` copies the 104-word context on every call, where the `match`
updates it in place. L0's kernel keeps `match` in exactly those functions
(`resume`, `kset`, `kresume`, `kmapped`, `run`, `give`). A field form that
takes the array out, as 6.5's row form does for arrays, is the candidate
next language item; until then, convert reads and the replacement of words
and lists, and leave arrays and maps inside records to `match`.

**The hidden whole copy applies to records.** Read first, replace last:
`(.n r (add (.n r) 1))` is in place, `(.n (.m r 1) (.m r))` copies `r`,
since the outer form reads `r` after the inner replacement.
`L0_ARRAY_STATS=1` on a run now counts record replacements with the array
updates; on L0S's heaviest loops, compare the count before and after a
conversion, and any copy per iteration is this trap.

## 3. `l0 fmt`

```bash
l0 fmt FILE.l0 ...          # rewrite in place
l0 fmt --check FILE.l0 ...  # only report; exit 1 if anything would change
```

Where a line of code dedents below the line a form began on, and where a
new declaration begins at column 0, it adds the closers still missing at the
end of the line before, and it drops closers with nothing to close. It
changes nothing else: every closer written stays, nothing is re-indented,
strings and comments are kept. That fixes the run of a dozen at the end of a
`def`, which is where the count goes wrong. It deliberately does not infer
every closer from indentation, as Parinfer does, because L0 is written in
shapes that would mislead: flat `if` chains at one indentation, a match
arm's body indented past the arm's `(`, hanging `append` chains, operands
aligned under the `(` of the form they continue. All of L0's own 241 files
come back byte-identical. A closer missing inside a form whose next line is
as deep or deeper is left as written; `l0 check` then reports it, and says
by how many the declaration's count is off and at which line it probably
went wrong (section 5).

The working loop for an agent: write, `l0 fmt`, `l0 check`, `l0 test`. A
file that is already right is unchanged, so running it on everything is
safe. One worked example: a `def` whose last line is one closer short, with
the next `def` at column 0 after it, comes back with the closer added to
that last line.

## 4. A `let` of several bindings, and an `if` of several tests

```
(def chain ((x int)) int
  (let (a (add x 1) b (mul a 2) c (sub b 3))
    (add a (add b c))))

(def grade ((n int)) (list int)
  (if (ge n 90) "a"
      (ge n 80) "b"
      (ge n 70) "c"
      "f"))

; A chain in tail position is a tail call in each value, so a loop written
; as one runs without growing the stack.
(def count_down ((n int) (acc int)) int
  (if (eq n 0) acc
      (eq (mod n 2) 0) (count_down (sub n 1) (add acc 2))
      (count_down (sub n 1) (add acc 1))))
```

`(let (n1 v1 n2 v2 ...) body)` is exactly `(let n1 v1 (let n2 v2 (...
body)))`, each value seeing the names before it, and `(if c1 e1 c2 e2 ...
else)`, an odd number of operands, is exactly the nested `if` chain. Both
are desugared by the parser, so everything else about them, types, tail
calls, reference counting, is as for the nested forms. The one-name `let`
and the three-operand `if` are unchanged.

**Where L0S gains.** Lines ending in a run of nine or more closers, 1,099 in
L0S:

```bash
grep -rnE '\){9,}$' --include='*.l0' .
```

Most such runs close a nest of `let`s, which one `let` of several bindings
closes with two. And `(if` lines followed by an `(if` line at the same
indentation, the flat chain, about 779 in L0S:

```bash
grep -rnB1 -E '^ *\(if ' --include='*.l0' . | grep -cE '^[^:]*-[0-9]+- *\(if '
```

Each such chain is one `if` of several tests. Converting is optional and
mechanical; do it where a function is being touched anyway, and `l0 fmt`
then counts the shorter run.

## 5. The new diagnostics, and a fixed crash

When a declaration's parens do not balance, `l0 check` adds a line at the
declaration:

```
f.l0:6:1: error: f is missing 1 closing paren before the declaration at line 14; probably at the end of line 12
f.l0:5:1: error: f has 1 closing paren too many: it closes at line 11
```

The first guesses the line from the indentation; the second is exact. Stray
`)` after a declaration that closed are counted against it. A script that
matches diagnostics can rely on the shapes `is missing N closing paren(s)`
and `has N closing paren(s) too many`. The parser's `unclosed ( in a call`
and `in a parameter list` now name the `(` they mean, where they said line 1.

Fixed: a source file whose last byte is a digit, which is always invalid
since a program ends in `)`, crashed the compiler with `head of empty list`
instead of reporting the unclosed form.

## 6. A suggested order

1. Install, then `l0 check` and `l0 test` across L0S unchanged: they must
   pass as before.
2. `l0 fmt --check` across L0S: expected to change nothing; read any diff.
3. Fields, type by type, starting with the 429 accessor functions: convert a
   type, run its tests, and on the loops that use it compare
   `L0_ARRAY_STATS=1` before and after; a new copy per iteration means a
   record whose array or map is updated through a field read, which goes
   back to `match`.
4. The sugar where the closer runs are longest, as those functions are
   touched.
5. `L0_RC_CHECK=1` on a test run after each batch: it reports any block
   still live at exit, and any use of a freed one.
6. Functions as arguments (section 7), loop by loop, where two functions
   differ only in what they do to each element.

## 7. Functions as arguments (roadmap 0135)

A `def`'s parameter may have a function type, `(fn (T...) R)`, written only
there, and is given a `def` by name, or a function parameter passed on, and
called like a function. Spec 3, 5.7, 7, and 10.2. Nothing L0S compiles
changes meaning: a call resolves to a parameter only when it has a function
type, which no program had. From `tests/unit/fn_args_test.l0`:

```
(def (find_by K T) ((key (fn (T) K)) (k K) (xs (list T))) (Option T)
  (if (is_empty xs)
      ((None T))
      (if (eq (key (head xs)) k) (Some (head xs)) (find_by key k (tail xs)))))

(def (map_list A B) ((f (fn (A) B)) (xs (list A))) (list B)
  (rev (map_onto f xs (nil B))))

(find_by name_of "bob" (people))           ; name_of: Person -> (list int)
(map_list length (map_list name_of (people)))   ; length takes T; the list fixes it
```

What cannot be passed: a builtin (write a one-line `def` that calls it), an
expression, or anything that is not a name; a function cannot be returned,
kept in a list or a field, or bound with `let`, and there are no closures,
so a function that needs more than its arguments is passed that alongside.
Each `def` passed makes one copy of the callee, so every call is direct, a
tail call through a parameter uses no stack, and nothing costs more at run
time than the loop written out twice. The copies cost code size: a function
given three different `def`s is three functions.

The library gained one function with a function parameter, `find_by`
(`l0 doc find_by`), a lookup in a list by a key function; the compiler's
seven lookups are now it, each with a one-line key `def`.

**Where L0S gains.** The shape is two or more functions with the same
recursion that differ in one call, a lookup by a different key or a walk
that does a different thing per element. A first list, by name:

```bash
grep -rnE '^\(def (find|lookup|count|any|all|map|filter|sum)_[a-z_]+ ' --include='*.l0' . | sort -t' ' -k2
```

Collapse a family into one function with a parameter of function type, and
keep a one-line `def` per old name only where callers are many. What to
leave alone: a loop whose element work needs the caller's state, which a
closure would carry; pass that state as an argument instead only where it
reads naturally.
