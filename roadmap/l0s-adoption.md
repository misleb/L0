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
keeps `match`.

**A field that holds an array or a map, updated and put back**, converts
too, since roadmap 0136, in exactly this form: the field read is one
argument of the function whose result replaces it, and nothing else reads
the record in that call or after it. From `lib/examples.l0`:

```
; The map inside goes through map_put and back into its field: the field
; is taken out for map_put and the result put back (spec 6.5), so the map
; updates in place when nothing else holds s. Bound by a let first, or
; read by another argument too, the map would be held twice and copied.
(def space_put ((s Space) (page int) (frame int)) Space
  (.pages s (map_put (.pages s) page frame)))
```

and from L0's kernel, `tests/virt/user/kernel.l0`, whose six functions
that kept `match` for this (`resume`, `kset`, `kresume`, `kmapped`, `run`,
`give`) are now written with fields, measured at 0 copies over 10,000
rounds:

```
(def resume ((p Proc) (v int)) Proc
  (.state (.ctx p (call_result (.ctx p) v)) -1))

(def kresume ((k Kern) (i int) (v int)) Kern
  (.procs k (update_at resume (.procs k) i v)))
```

The form must be literal: `(let c (.ctx p) (.ctx p (call_result c v)))`
holds the context twice and copies it, and so does a read of `p` after the
replacement. An L0S toolchain before 0136 copies these on every call, so
convert them only on 0136's toolchain or later; `L0_ARRAY_STATS=1` on a
test run tells which one is installed. 0136 also fixed the array form,
`(array_set g y (f (array_get g y)))`, which gave `g` an empty element
afterwards when `g` was used after the `array_set`; grep L0S for the shape
where `g` is read again:

```bash
grep -rnE '\(array_set ([a-z_0-9]+) [a-z_0-9]+ \([a-z_0-9]+ .*\(array_get \1 ' --include='*.l0' .
```

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
   record whose array or map is updated through a field read not in the
   literal form of section 2.
4. The sugar where the closer runs are longest, as those functions are
   touched.
5. `L0_RC_CHECK=1` on a test run after each batch: it reports any block
   still live at exit, and any use of a freed one.
6. Functions as arguments (section 7), loop by loop, where two functions
   differ only in what they do to each element.
7. Word wrappers (section 8) for the handles a wrong int could be passed
   for, starting with spaces and frames.
8. Guards written as nested `if` only because `and` was strict (section
   9), as those functions are touched.

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

## 8. Word wrappers cost nothing (roadmap 0137)

A data type declared without type parameters, with one constructor of one
`int`, `bool`, or `float` field, is that word at run time (spec 10.1):
construction, `match`, and its field are the identity, and nothing about
it is counted. `IoFile` and `IoDevice` in the library are such types
already, and so is any of L0S's, with nothing to change. From
`tests/virt/user/kernel.l0`, whose spaces are now typed:

```
(data Space
  (Space (id int)))

(let s (Space (space_new))
  (if (lt (.id s) 0) ... (space_map (.id s) va f perm)))
```

**What changes.** `hash` of such a value is its field's, without the tag
item, and so is the hash of anything holding one. L0S's five `hash` calls
(`files.l0`, `tcpstack.l0`, `widget.l0` twice, `process.l0`) hash records
used as cache keys or a sequence number, and no test pins one, so nothing
depends on the values; a stored hash from before is not equal to one from
after.

**Where L0S gains.** Every handle kept as a bare `int` that a wrong one
could be passed for: spaces, frames, regions, interrupts, process and
window ids. Wrapping one is a `data` line and `(.id x)` at the builtins.
The library does not wrap the user-mode builtins itself: they take ints,
which are what the process ABI and every host pass, and a typed copy of
6.13's nineteen builtins would be a second interface to keep in step,
where a program's own one-line type costs nothing. L0S's existing wrappers:

```bash
grep -rnE '\(data ([A-Z][A-Za-z0-9_]*)[[:space:]]*\(([A-Z][A-Za-z0-9_]*)[[:space:]]+(\([a-z_0-9]+[[:space:]]+)?(int|bool|float)\)?\)\)' --include='*.l0' .
```

## 9. `and` and `or` stop at the operand that decides (roadmap 0138)

The builtins `(and a b)` and `(or a b)` evaluate `b` only when `a` does not
decide: when `a` is `true` for `and`, `false` for `or` (spec 8). A `def`
named `and` or `or` is unchanged. From `tests/io/and_or_short.l0`:

```
(def guard ((xs (list int))) bool
  (and (not (is_empty xs)) (gt (head xs) 0)))     ; never takes head of empty
```

**What changes.** A second operand with an effect, a write, a read, a
region or space access, an interrupt, or a kernel call, no longer happens
when the first decides. None of L0S's does; this finds one, and found none
on 2026-10-30:

```bash
grep -rnE '\((and|or) .*\((write_|read_|file_|space_|region_|user_run|supervisor_|frame_|interrupt_|timer_at|cpu_run|clock_ns)' --include='*.l0' .
```

A runtime error in a second operand that the first decides no longer
happens either, which is the point. The second operand is still not in tail
position, so a loop through `or` is still written with `if`.

**Where L0S gains.** Guards written as a nested `if` only because `and`
evaluated both sides, `(if (is_empty xs) false (gt (head xs) 0))`, read as
the `and` they mean; convert them as the functions are touched.
