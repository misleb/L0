# L0 specification changelog

Every change to the language is recorded here, with the reason it was made. The
spec itself ([L0.md](L0.md)) says only what L0 *is*; this file says why.

New entries go at the top.

An entry may cite a prototype under `roadmap/NNNN/`, which is deleted when
the item that uses it lands, or a scratch file under `tmp/`, which was never
tracked. Those cited and since deleted can be read at the commit before
their deletion: `roadmap/0026/bench/` at 66a8dd4, `roadmap/0068/metal.ll`
at b87e7c2, `roadmap/0074/progs/` at dfdd1fe, and `roadmap/0094/why.l0` at
0f98c2e (`git show 0f98c2e:roadmap/0094/why.l0`). The `tmp/0110/` programs
of the Pi 5's first runs were not kept; their entries quote what they read.

---

## The library's regions are called regions, and no language change for it (roadmap 0144)

**Changed:** `lib/io.l0` states one naming rule in its header, and its
region wrappers follow it: `IoRegion`, `IoRegionOpened` with
`IoRegionOpened` and `IoRegionFailed`, `RegionFault` with `RegionMissing`
and `RegionNoRoom`, `open_region`, `close_region`, `region_get8` to
`region_get64`, `region_set8` to `region_set64`, `region_get_bytes`, and
`region_set_bytes`. Every old name, `IoDevice`, `DeviceOpened`,
`open_device`, `device_read32` and the rest, is kept as an alias, a type
beside the new one and a `def` calling the new function, documented as the
old name, so nothing that compiled stops compiling.

*Why:* the spec calls them regions and the library called them devices,
and the constructor pairs, `IoOpened`/`IoFailed` against
`DeviceOpened`/`DeviceFailed`, differed in shape, while `lib/io.l0`'s own
header stated a rule its newer types broke. The review found it; L0S uses
the device names in 41 files, so a rename without aliases would have
broken all of them.

*Decided:*
- *`region_get32` and `region_set32`*, since `region_read32` is the
  builtin's name, and a library function of a builtin's name would take it
  from every program (spec 7); get and set are what `array_get` and
  `array_set` say of an indexed thing.
- *Left as they were:* `open_appending`, since `open_append` is a builtin;
  `IoLine`'s `IoError`, which the rule allows as an `Error` ending; and
  `Trap`, which names what the CPU did. Renaming them would have cost a
  second set of aliases for no rule's sake.
- *Aliases cost nothing:* `IoDevice` and `IoRegion` are word wrappers
  (0137), and each alias inlines.

---

## and and or evaluate their second operand only when it matters (roadmap 0138)

**New:** the builtins `(and a b)` and `(or a b)` evaluate `b` only when `a`
does not decide the result (spec 6, 8); a `def` named `and` or `or` is
called as before. `b` is still not in tail position.

*Why:* strictness bought nothing a program could want, and cost a trap
the skills had to warn of: `(and (not (is_empty xs)) (gt (head xs) 0))`
took the head of the empty list, so the guard had to be a nested `if`.
The trap caught the compiler itself, whose lexer's `(and (not (is_empty
rest)) (is_name_rest (head rest)))` crashed on a source file ending in a
digit (changelog, "A declaration's miscounted parens are counted").

*Decided:*
- *Only the builtins.* A `def` of the name keeps being a function, both
  arguments evaluated, so section 7's shadowing means what it did.
- *`b` not in tail position.* Making it one would let `(or done (loop
  ...))` be a tail call, which reads well, but would change which
  functions share a tail-call component (10.2) for every such program; it
  waits for a program that needs it.
- *Stage 0 keeps the strict reading.* It is frozen, so
  `tests/lang/err_and_strict`, which pinned the strict reading, leaves the
  differential suite: its program now gives `false`, which
  `tests/io/and_or_short` checks, with an effect in each second operand.

---

## A one-field wrapper of a word is the word (roadmap 0137)

**New:** a *word wrapper*, a data type declared without type parameters
with one constructor of one field of type `int`, `bool`, or `float`, such
as `(data Space (Space int))`, is represented as its field's word (spec
10.1): constructing one, matching it, and reading or replacing its field
are the identity, and nothing about it is counted. `eq` and `compare` are
unchanged, being the field's already; `hash` loses the tag item, so it is
the field's hash (6.9).

*Why:* spec 6.12 says regions, handles, spaces, frames, CPUs, and
interrupts are numbered apart and "neither is ever the other", and the
checker could see none of it, since wrapping an `int` in a data type
allocated a block with a header and a tag for every value. So the builtins
took bare ints and a kernel kept them, and passing a frame where a space
was due was `not a space` at run time rather than a compile error. The
library wrapped two, `IoFile` and `IoDevice`, and paid for it at every
call. The smallest program that could not be written without the cost: a
kernel whose spaces and frames are different types.

*Decided:*
- *By the declaration, not by a keyword.* Every such type is a wrapper,
  so `IoFile`, `IoDevice`, and any program's already are, with nothing to
  write; the only thing a program can observe is `hash`, which changes.
- *Only `int`, `bool`, and `float` fields, and no type parameters.* A
  field of a counted type would make the wrapper counted or not by its
  field, and a type parameter would make it a wrapper at some types only;
  neither earns its rules yet.
- *Done after checking*, by giving a wrapper's type a name no source can
  write, as `group_upper` and `hide_tparams` do, so that whether a type is
  counted stays a question about the type alone.
- *`hash` changes.* Keeping the tag item would have meant hashing a word
  as if it were a block, for no gain. L0S calls `hash` five times, each
  on a record used as a cache key or a TCP sequence number, and pins none
  in a test, so a record holding a wrapper hashes differently and nothing
  depends on which.

*Used:* the L0 kernel's spaces are a `Space` wrapper, and the checker
found each of the 11 user-mode builtin calls that was given one. The
library adds no typed spaces or frames: the builtins take what the process
ABI and every host pass, a typed copy of them would be a second interface,
and a program's own wrapper is a line that now costs nothing. Self-compile
went from 0.69 s to 0.71 s, for the new code, since the compiler has no
wrapper of its own.

---

## A field goes through a function and back in place (roadmap 0136)

**New:** `(.f r (g a1 ... (.f r) ... an))`, with `r` one variable that no
other argument of `g` mentions, takes the field out of `r` for `g` when
nothing else holds `r`, and puts `g`'s result back, as 6.5's form does for
an element of an array (spec 5.8, 6.5). One runtime function,
`l0_data_take(b, i)` (10.3), beside `l0_array_take`, append-only.

*Why:* a field holding an array or a map, updated and put back, copied
when written with fields: in `(.ctx p (call_result (.ctx p) v))` the read
held the context while `p` did too, so `call_result`'s `array_set` copied
its 104 words on every system call. So 0132's step 2 left `match` in the
L0 kernel's `resume`, `kset`, `kresume`, `kmapped`, `run`, and `give`, and
in the examples' `space_put`, each with a comment saying why. The smallest
program that could not be written in place:

```
(def resume ((p Proc) (v int)) Proc
  (.state (.ctx p (call_result (.ctx p) v)) -1))
```

*Decided:*
- *The row form's rule, not a new one.* Spec 6.5 already said when an
  element is taken out and put back; a field is that with the index fixed
  by the name, so the conditions are word for word the row form's, and
  so is the reason it is safe: nothing can read `r` while `g` runs.
- *Only a field of a counted type is taken*, since a word that is not a
  pointer has nothing to share; for those the form is the plain reading.
- *No new syntax.* The written form is what a reader would write, and
  what `match` did is now what fields say.

*Also fixed:* the array form, since 0076, took the element out of `g` even
when `g` was used after the `array_set`, which spec 6.5 counts as another
holder: in `(let h (array_set g 0 (push9 (array_get g 0))) (array_get g
0))` the last read gave the empty list where it should give the element.
The field form's first test hit the same mistake, `fields_test`'s
`(.tags r (cons "c" (.tags r)))` with `r` read again after. Both forms now
take only when the outer update is the variable's last use, and
`array_test` has the case.

---

## Functions as arguments, by one copy per function passed (roadmap 0135)

**New:** a `def`'s parameter may have a function type, `(fn (P1 ... Pn)
R)` (spec 3), written only there. It is given a `def` by name, or a
function parameter of the caller passed on, and called like a function,
`(key x)` (5.7); a call resolves to a function parameter first, when the
innermost local of its name is one (7). Each function with function
parameters compiles to one copy per combination of kinds and of `def`s
passed, only those some call reaches, and a call through a function
parameter in a copy is a direct call of that `def`, `fastcc` and
`musttail` as any other (10.2).

*Why:* a function could not be passed to another, so every loop that
differs only in what it does to each element was written out again. The
compiler had seven copies of one lookup (`find_bind`, `find_sig`,
`find_ctor`, `find_data` in check.l0; `lookup_operand`, `lookup_type`,
`lookup_read_only` in emit.l0); `l0 test` found a program's tests with
`sed` and generated a `main` that dispatched on their names; and sorting by
a key meant declaring a key type. The smallest program that could not be
written was a lookup by a key function, once:

```
(def (find_by K T) ((key (fn (T) K)) (k K) (xs (list T))) (Option T)
  ...)
```

which the checker rejected with `expected list, array, or a data type name
after ( in a type`.

*The four rejections, answered.* The changelog turned function values down
four times, for `compare` (0059, 0064), for handles (0020), and for type
parameters. Each objection follows from functions being values at run time,
and here they are values only at compile time:
- *Indirect calls, and an exception to section 8's tail calls.* There are
  none: within a copy every call through a parameter names its `def`, so a
  tail call there is a `musttail` call between two functions of one
  padded component, as any other.
- *A wrapper per function used as a value, with owned arguments.* There is
  no wrapper: the `def` itself is called, with its own read-only
  parameters and the release rule unchanged.
- *Name resolution stops being syntactic.* It is still syntactic: a call
  resolves to a function parameter only when the innermost local of its
  name is one, which the declaration's parameter types say, and a program
  with no function type resolves as it did.
- *A generic function passed as a value has no argument to take its types
  from.* It takes them from the function type it is passed at: the call's
  other arguments are matched first, and by then the type the passed
  function takes is fixed, or the call is an error.

*Decided:*
- *The form `(fn (T...) R)`*, a type in parentheses like `list` and
  `array`, with `fn` not reserved, as `bytes` and `float` are not, since
  programs use `fn` as a name (`emit_rt_call`'s parameter, for one).
- *Only at the top of a parameter's type.* A function type in a field, a
  list, or a return type would make a function a value that outlives the
  call, which is a closure without its environment, or an indirect call.
- *A `def` or a passed-on parameter, not a builtin.* A builtin has no one
  type (`eq` and `cons` take any) and no symbol to call, and one that a
  `def` of the callee's group shadows would resolve differently inside the
  copy than where it was named. A one-line `def` passes one; it inlines.
- *Function arguments matched last.* That is the whole of what passing a
  generic function needs, and it keeps checking a left-to-right match with
  no unification: the passed function's parameter types must be complete
  when it is reached.
- *Copies per `def` passed, named for it with its group,* `.F` or `.P`,
  so a prelude function given a program's `def` calls that one even where
  the prelude has a function of the same name, and the names cannot
  collide: kind digits come first, and every part for a function starts
  with an uppercase letter.
- *Only copies some call reaches.* A function with function parameters has
  no code of its own, since a parameter of function type has no value.

*Used:* after the seed was refreshed, the prelude gained `find_by`, and
the compiler's seven lookups became `find_by` with a one-line key function
each, six copies of it in the compiler's IR. Self-compile went from 0.68 s
to 0.69 s and the compiler's IR from 2,042,788 to 2,044,056 bytes. Its
`Expr` walks were not folded: without a wildcard arm each still needs its
whole `match`, and each carries state of its own, so a fold read worse.
`l0 test` still generates a `main`: passing a function does not let a
program list its own functions, which finding its tests needs.

*Left open:* builtins as arguments; a function that takes a function
parameter itself being passed; closures, which 0028's sort of lines by an
index into one buffer would want, and which a parameter for the buffer
expresses meanwhile.

## Named fields: a value's field read and replaced by name (roadmap 0132)

**New:** a constructor may name its fields, `(data Proc (Proc (space int)
(ctx (array int)) (state int)))`, all of them or none (spec 4). A field
name is a token of its own, `.` and a lower name (2.4). `(.state p)` reads
the field and `(.state p -1)` is `p` with that field replaced (5.8), on a
data type with one constructor; `e`'s type says which field it is, so no
inference and no declaration to resolve against. Construction and `match`
stay positional. A replacement consumes its value, as `array_set` consumes
its array, and stores in place when nothing else holds it, by 6.5's rule;
`L0_ARRAY_STATS` counts it with the array updates. One runtime function,
`l0_data_with` (10.3), append-only; a read is `l0_data_get`. A field read
of a type that is not counted keeps a parameter read-only, as `head` of
such elements does.

*Why:* the compiler had 47 one-line functions whose whole body is a
single-arm `match` returning one field (`ctx_sigs` to `data_max_fields`,
check.l0; `env_binds` to `val_st`, emit.l0), and the L0 kernel wrote
`(Kern ps q qo arr held pa)` 22 times to change one field of a six-field
value (tests/virt/user/kernel.l0). A review of the language found both,
and that no program had earned function values or records in the
changelog's terms only because the cost was paid a line at a time. The
smallest program that could not be written is a process's state read and
set without a function per field.

*Decided:*
- *A token, not a reserved word.* `(get p space)` and `(set p space v)`
  read as English, but `get` and `set` are names programs may already
  use, and section 7's reason for never taking names from programs holds.
  `.name` was a lexical error, so no program changes meaning.
- *Not `(Proc.space p)`.* The constructor is redundant: `p`'s type names
  it, by the rule every expression already follows (5.4).
- *One constructor only.* Every accessor in this repository is on a
  one-constructor type; a type with several keeps `match`, which is what
  makes a new constructor a compile error at every site. Access across
  constructors that share a field is left open.
- *All of a constructor's fields named, or none.* A mix would leave some
  fields reachable only by position, and the reader counting.
- *Replace in place by the existing rule*, not a new one: 6.5 already
  says when an update copies, and the hidden-whole-copy trap applies to
  records exactly as to arrays and maps. Measured on a scratch program,
  a loop of 1,000 steps that read the record in a later operand of its
  replacement made 2,001 copies; written to read first and replace last,
  none.
- *Field names are no namespace.* They resolve through the type alone,
  so a function, binding, type, or constructor of the same name is
  unrelated, in either prelude group, and the prelude can name fields
  freely.

*Left open:* access on types with several constructors; named `match`
arms; replacing several fields in one form, which nests for now.

*Compiled by:* the seed from before this entry cannot compile a field,
so by the two-step rule the compiler and the prelude used none until the
seed was refreshed. Then, in roadmap 0132's step 2, the compiler named the
fields of its record types, `Ctx`, `CtorInfo`, `DataDef`, `Sig`, `Ctor`,
`Arm`, `Emit`, `EmitVal`, `Env`, `MatchCx`, `RoCx`, `Scope`, `Pad`,
`RoFn`, and `FileEntry`, and deleted the accessors, 47 functions; the
kernel named `Proc`'s and `Kern`'s; and the examples gained `Proc`.

*Found in step 2:* a field that holds an array or a map, updated and put
back, is still taken apart by a `match`: `(.ctx p (call_result (.ctx p)
v))` reads the context while `p` holds it too, so `call_result`'s
`array_set` copies the 104 words, where `(match p ((Proc s c m w st) (Proc
s (call_result c v) m w -1)))` releases `p` once it has the fields and
updates in place. Section 6.5's third form takes an element out of an
array for exactly this, `(array_set g y (f (array_get g y)))`; the field
analogue, `(.f r (g (.f r)))` with `r` one variable no other argument
mentions, is the natural next step, and until it exists the kernel's
`resume`, `kset`, `kresume`, `kmapped`, `run`, and `give` and the
examples' `space_put` keep their `match`, with a comment saying why.

---

## A let of several bindings, and an if of several tests (roadmap 0134)

**New:** `(let (n1 v1 n2 v2 ...) body)` is exactly `(let n1 v1 (let n2 v2
(... body)))`, and `(if c1 e1 c2 e2 ... else)`, with an odd number of
operands, is exactly `(if c1 e1 (if c2 e2 (... else)))` (spec 5.2, 5.3,
and 8). Both are desugared by the parser into the nested forms, so the
checker, the emitter, the runtime, and the seed's interface do not change,
every rule stated of `let` and `if` follows from the nesting, and the
one-name `let` and the three-operand `if` stay as they were. A list of
bindings with no pairs or an odd count, and an `if` with an even number of
operands, are compile errors.

*Why:* nesting is what makes closers hard to count. A chain of six `let`s
closes with seven parens; runs of 9 to 19 end about 50 lines of the
compiler and the kernel, whose nesting reaches 15 to 19; and the review
that opened 0132 found miscounted closers "the cause of every parse error
hit while writing the compiler" (the l0-code skill). `l0 fmt` (0133)
counts the run at the end; this shortens it. The `if` chain is already
L0's idiom for a chain of tests, written flat with every `(if` at one
indentation (`dispatch_form`, `escape_byte`); the form says what the
layout meant.

*Decided:* sugar in the parser, not new forms in the checker, so that
nothing about types, tail position, or reference counting is said twice;
the nested forms carry the `(`'s offset, so a diagnostic in a chain names
the chain. Not a `cond` with a keyword, which would reserve a word
(section 7's reason), nor bindings in pairs of parens, `(let ((a 1) (b
2)) ...)`, which gives back as many parens as it saves.

*Compiled by:* the seed from before this entry cannot compile either form,
so by the two-step rule the compiler and the prelude use neither until the
seed is refreshed.

---

## l0 fmt adds the closing parens the indentation shows missing, and no language change for it (roadmap 0133)

**New:** `l0 fmt FILE...` rewrites each file with the closers its
indentation shows missing added at the ends of its lines of code, and
closers with nothing to close dropped, and nothing else changed; `l0 fmt
--check` only reports. The program is `tools/fmt.l0`, with its `main` in
`tools/fmt_main.l0`, built by `tools/install.sh` beside the compiler as
`l0fmt`. `tests/unit/fmt_test` covers the rule and `tests/io/fmt` runs it
over every `.l0` under `compiler/`, `lib/`, and `tests/virt/user/`, which
come back byte-identical; so do all 241 L0 files in the repository.

*Why:* miscounted closers are the most common way an agent wastes time in
L0, and counting a run of identical tokens against context lines away is
what a model does worst, where judging that one line is indented under its
parent is what it does well.

*Decided: the rule is weaker than Parinfer's.* Parinfer's indent mode drops
every trailing closer and infers them all from the next line's
indentation. Tried first, it changed 57 of 163 files, because L0 is
written in shapes it cannot tell from a missing closer: a chain of `(if
...)` or `(yn ...)` lines at one indentation, each the last operand of the
one before (`dispatch_form`, the `tests/lang` suites); a match arm's
`((Ctor fields) body)` with the body indented past the arm's `(`; a form
late on a line continued on the next, indented past the line but not as
far as the form, as the compiler's `append` chains are; and an operand
aligned under the `(` of the form it continues (`check_errors.l0`'s
nested `push`es). So every written closer is kept, and a form is closed
only where the next line of code dedents below the line the form began on,
or begins a declaration at column 0. That fixes the run at the end of a
`def`, which is where the count goes wrong, and leaves a closer missing
inside a form whose next line is as deep or deeper to the checker, which
now reports it with a count. Two files changed to be consistent with
their own indentation: `lib/test.l0` gained its final newline, and
`check_errors.l0`'s final `(rev da)` moved under the `push`es it closes.

*Made possible by 0132:* the formatter's state is a six-field record read
and replaced by name; it is the first program written with fields.

*Also fixed, found by it:* in a checkout, every `l0` command rebuilds
`lib/l0c` when the seed is newer, and the test suite's parallel jobs all
found it so at once after a seed refresh, each running the installer over
the others' half-written files; four board tests failed that way once the
installer also built `l0fmt`. `tools/l0` now takes a lock, a directory
`lib/.building`, so one command rebuilds and the rest wait.

---

## A declaration's miscounted parens are counted, and no language change for it

**New:** when a declaration fails to parse and its tokens, up to where the
next declaration begins, do not balance, the compiler adds a diagnostic at
the declaration: `f is missing 2 closing parens before the declaration at
line 14; probably at the end of line 12`, or `f has 1 closing paren too
many: it closes at line 11`. The guess for a missing closer is the end of
the last line before the first line not indented past the innermost form
still open where it starts, since L0 as written here indents every line
under its parent; the line a declaration closes early on is exact. Stray
`)` after a declaration that closed are counted against it. `DParens` in
parse.l0, rendered in main.l0; `tests/check/parens_*`. The parser's
"unclosed ( in a call" and "in a parameter list" now report the `(` they
mean rather than offset 0.

*Why:* miscounted closers were "the cause of every parse error hit while
writing the compiler" (the l0-code skill), and the error was reported at
the *next* declaration with no count, so a fix took two rounds. Lines of
the compiler and kernel end in runs of up to 19 closers.

*Also fixed:* the lexer called `head` on the empty rest of the input when a
source file's last byte was a digit, through a strict `and` (lex.l0:303 and
:326), the trap the skills warn of, in the compiler itself; such a file is
always invalid, since a program ends in `)`, but the compiler crashed
instead of saying so. `tests/check/eof_digit` and `eof_float`.

---

## The hidden whole copy, named where an agent will see it (roadmap 0131)

**New:** nothing in the language. Spec 6.5 now names the case of a value
used after a call that updates an array or map inside it, which followed
from its rules but only by reading two of them across a call, and
section 6's table says `array_set` copies when something else holds the
array. The `l0-code` skills, `lib/AGENTS.md`, the Map's and `map_put`'s
and `map_remove`'s comments, and `lib/examples.l0` show both shapes.

*Why:* L0S asked (its `build/l0-requests.md`, request 4). It hit the copy
twice in one session, both seen only as a slowdown on real data:
`(Pages (map_put m va f) (if (map_has m va) ...))`, which copied the map
on every put and made a test of 12 s not end in an hour, and a process
value used after a call that updated a map inside it. Measured here with
`L0_ARRAY_STATS=1`, 20,000 puts of the first shape made 39,998 copies of
1.2 billion words in 1.6 s, against none in 5 ms read first.

*Decided:* the documentation first, as the request offered. Whether
`l0 check` should warn of an update that a later use makes copy is left
open in roadmap 0131: it would be L0's first warning.

---

## A frame is zeroed a cache block at a time, by dc zva on aarch64 (roadmap 0129)

**New:** the boards' hosts zero a page for a frame or a table through a
hook of the CPU's part: on aarch64 by `dc zva`, a block at a time, the
size `DCZID_EL0` gives, or by stores if it says `dc zva` is prohibited;
on riscv64 by stores. The freestanding `memset` stores whole words from
the first aligned address. Spec 6.13 says that a new frame's zeros, like
any CPU write, reach a device that does not go through the caches only
after `frame_sync` with 1 or 3.

*Why:* L0S asked (its `build/l0-requests.md`, request 1). On a Pi 5,
8,192 `frame_new` calls took 22.4 ms, 2.75 us a frame, about 1.5 GB/s,
against 0.05 us for each `space_map`; a 4K compositor's buffers of 8,000
to 13,000 pages cost 22 to 35 ms of it while every CPU's system calls
wait on CPU 0, and L0S had to keep a pool of frames zeroed while idle.

*Found:* the request supposed zeroing went a byte at a time. It did not:
LLVM vectorizes `memset`'s byte loop at `-O2`, and the page was zeroed by
32-byte `stp q0, q0` stores already. What stores cannot avoid is reading
each line from memory before it is overwritten, for a page not in the
cache, which is every new frame. `dc zva` makes the line zero in the
cache without reading it, which is why Linux's `clear_page` uses it.
`memset`'s word stores matter only where LLVM does not vectorize, and
make its tail no longer a byte at a time.

*Measured:* on QEMU's aarch64 virt board, which emulates `dc zva` with a
helper call and has no cache to miss, `frame_new` went from about 990 ns
to about 1,790 ns, and with stores alone stays about 1,000 ns: QEMU says
nothing of the board. On a Pi 5, in ns a `frame_new`, `dc zva` against
stores alone: 256 fresh frames, 243 against 281; the same 256 again, in
the cache, 101 against 137; 8,192 fresh, 32 MB, 2,669 against 2,709. So
zeroing is fast until the caches fill, and then costs what writing the
lines back to DRAM does, about 1.5 GB/s, by any instruction: L0S's 8,192
frames were past every cache. `dc zva` is kept for being faster within
them and no slower past them; a kernel that needs many frames at once
keeps zeroing them while idle, as L0S does.

---

## A space has a high user range, 128 GB past the 4th gigabyte (roadmap 0128)

**New:** on the boards' hosts the user range (spec 6.13, 10.3) is two
parts: the low user range, 0xC0000000 up to 0x100000000, as before, and
the high user range, 0x2000000000 up to 0x4000000000, 128 GB, the root
table's entries 128 to 255. A space makes the tables for the high part
only as pages there are mapped. A process's layout keeps its image, heap,
and stack where they were, and the high part is the kernel's to map into,
beside 0xE8000000 up to 0x100000000. A `space_read` or `space_write`
lies within one part.

*Why:* L0S asked (its `build/l0-requests.md`, request 2, for its roadmap
0038). At 3840x2160 and scale 2 its compositor maps every window's
buffers, a few tens of MB each, into the 384 MB a process had above its
stack. With five windows open, 84,000 of its 98,304 pages there were in
use, the largest free run 5,592 pages, and the next window's buffer of
11,387 pages could not be shared with it, so the window froze. More room
there is what any compositor or file cache needs, not only this one.

*Decided:* a second part rather than one range moved or grown. Growing
the 4th gigabyte upward runs into RAM, which the host maps from the 5th
gigabyte on the riscv64 board and to the 16th on the Pi 5; moving the
whole range would move every process's image, heap, and stack, and break
every process built so far and every kernel that loads one. Entries 128
to 255 are free on every board: the aarch64 board's map uses 0 to 2 and
256, the riscv64 one's 0, 2, and 4, and the Pi 5's up to 15, 64, 65, and
124. 0x4000000000 is also the end of Sv39's lower half, past which a
riscv64 address must be sign-extended, so the part is the most all three
CPUs' three-level tables can give alike. 128 GB is 340 times what the
compositor needed; up to 512 GB was asked, which Sv39 cannot give below
its sign bit. A kernel that maps nothing there pays nothing: no table is
made until a page is.

---

## The Raspberry Pi 5's display interrupt controller, disp_intr, is a region, with its interrupt (roadmap 0127)

**New:** on the Pi 5, `disp_intr`, the display's level-triggered L2
interrupt controller (`brcm,bcm2711-l2-intc`), is a region (spec 10.3),
0x107C502000 and 0x30 bytes, in the boot map's block 65. Its interrupt,
the GIC's SPI 97, is interrupt 129, level. From `bcm2712.dtsi`, node
`disp_intr: interrupt-controller@7c502000`; the `hvs` node names it as
its interrupt parent, with lines 2, 9, and 16 its channels' ends of frame.

*Why:* L0S asked (its `probes/display/REQUEST-pi5-hvs-eof.md`). Its
`hvs` driver could tell a display list had been taken only by polling
the channel's `DL` register for up to 50 ms after each restack, and its
paced display queue needs to change lists between frames and say which
frame showed a change. On SCALER6 the HVS has no end-of-frame register:
Linux's `vc4_hvs.c` enables and disables the line at this controller.

*Decided:* the controller and its interrupt, as asked, rather than the
smaller alternative the request named, pixel valve 0's own interrupt,
SPI 101. That one marks HDMI0's vertical blank, not the HVS taking a
list, which is what swapping lists safely needs; it can be given later
if a driver wants vblank too. The controller has a page to itself, so
the region reaches nothing else. Its clock is the display's, so the
HVS's rule, read only on a board that booted with a monitor, covers it.
No deliberate restriction is broken: these are a device's registers and
its interrupt, and reach no memory. No emulator has this board; it is
checked by building, and a first run is the user's.

---

## A region's bytes are copied out as bytes, and bytes into it (roadmap 0126)

**New:** `(region_read_bytes r off n)` returns the `n` bytes of region `r`
from `off` as bytes, and `(region_write_bytes r off b i j)` copies bytes
`i` up to `j` of `b` into `r` from `off` (spec 6.12). Each byte is read
or written once, lowest address first, in accesses of widths the host
chooses, so neither has an alignment rule. A negative count is `byte
count out of range`, a bad range of `b` is `byte index out of range`, and
both are checked after `not a region` and before `region offset out of
range`, as `space_read` and `space_write` check theirs after `not a
space`.

*Why:* L0S asked (its `probes/bytes/REQUEST-region-bytes.md`). Its file
server and drivers move bulk data through shared and DMA pages, which a
process reaches only as a region: a 64 KB write through a file window
was 65,536 `region_read8` calls and as many cons cells for
`bytes_from_list`, and going back the other way a `region_write8` a
byte. A kernel already had `space_read` and `space_write` for the same
job; a process had nothing alike.

*Decided:* the two take the shapes of `space_read` and `space_write`, a
count to read and a range of bytes to write, so a program that copies
through a space and one that copies through a region read alike. They are
for memory, not registers, and say so: a register's width is part of what
it means, and these give no width. The runtime copies a byte at a time,
each access volatile so that no copy is merged, left out, or turned into
a library call the host may not have, and wide or unaligned accesses
never reach memory mapped as a device's, which faults on aarch64 when
they are unaligned. The spec leaves the widths to the host so that
copying a word at a time can come later without a language change. 6.12's
paragraph that no region builtin yields bytes now says what does, and why
it still points nowhere: the bytes are a copy, as `space_read`'s are.

---

## The Raspberry Pi 5's SD host controller, sdio1, is a region, with its interrupt (roadmap 0125)

**New:** on the Pi 5, `sdio1`, the BCM2712's SD host controller behind
the microSD slot, is a region (spec 10.3), 0x1000FFF000 and 0x600 bytes,
in the boot map's block 64: SDHCI's standard registers, then at 0x400
the brcmstb `cfg` block. Its interrupt, the GIC's SPI 273, is interrupt
305, level. From the board's device tree, `bcm2712-rpi-5-b.dtb`, node
`sdio1: mmc@fff000`.

*Why:* L0S asked (its `probes/storage/REQUEST-pi5-sdio.md`), to keep its
files on the board's own card rather than in memory lost at every power
cut. Its `sdhci` driver already drives a standard SDHCI on QEMU; nothing
reached the Pi's. RP1's two SDHCIs are reachable through RP1's region,
but the device tree disables both, and neither is the slot's.

*Decided:* one region over both of the node's blocks, since they share a
page nothing else uses and a driver needs both. Its interrupt is offered
from the start, as dma40's was, though a driver may poll at first. The
card's power, its signalling voltage, and its detect pin are in
`gio_aon`, which is left out: that block also holds `RP1_RUN` and the
PMIC's lines, and the firmware leaves the card powered at 3.3 V. If a
board run finds otherwise after a network boot, a narrower region for
those pins is a later request. No deliberate restriction is broken: the
controller's SDMA and ADMA2 can write memory, but so can dma40 and the
HVS, and on a board only a program trusted with devices opens a region.
No emulator has this board; the region is checked by building, and a
first run is the user's.

---

## A program can ask how much of its heap is left (roadmap 0124)

**Changed:** a builtin, `(heap_left)`, section 6.19: how many bytes of
the program's heap are free, or -3 where the heap is an operating
system's. The runtime gains `l0_heap_left` and the host interface
`l0_host_heap_left`. The runtime now counts the bytes on its free lists
as blocks go on and come off them, and `freestanding.ll` the bytes in its
free blocks.

*Why:* L0S's `probes/memory/REQUEST-heap-left.md`. Its kernel records
every page it gives a process in its own heap, and its rule is that
nothing a process does can crash it. With a 96 MB kernel heap, its board
test `test_frames_run_out`, four processes taking 2,112 MB of a
1,839.5 MB pool, ends in `heap exhausted` before the frames run out, and
the board stops; with 192 MB the frames run out first and the test
passes. On a Pi 5 the kernel's heap is sized for 2 GB of RAM, and on a
board of more, processes can take more pages than it can record.
`frame_free_count` already lets the kernel refuse a page when frames run
out; nothing told it the same of its heap, whose size is fixed when it is
linked and whose state only the runtime sees. An estimate in L0S, about
285 bytes per page given, misses messages, maps, and the initramfs's
copy, and an estimate that is wrong stops the board.

*Decided:*

- Free bytes, not the largest value that can be made. The request
  accepts either for a kernel that allocates in small pieces, and free
  bytes is one number a program can reason about: what it frees comes
  back, what it makes goes. The largest block would need a walk of the
  host's bins or the free lists on every call, and would still not say
  whether a chunk could be made, which is when `heap exhausted` comes.
  6.19 says the count can overstate what one allocation gets, and that a
  reserve of a few megabytes is how a program stays clear.
- Blocks on the free lists count. Without them, a kernel that ends a
  process and frees its records would see nothing come back until a
  sweep, and sweeps run only as chunks are made, which a kernel that
  refuses work because its count is low never does: it would refuse for
  ever. Counting them costs an addition as a block is freed and a
  subtraction as one is reused, beside the stores to the list head those
  already make, so 10.3's "nothing is counted as blocks come and go" is
  now "only the free lists' bytes are". A sweep subtracts the bytes of
  the chunks it takes, which then count whole, as a chunk kept or as the
  host's free bytes, so a sweep never lowers the count.
- Asking never sweeps. A sweep walks every free list, and a kernel asks
  on every page it maps; the count is already right without one.
- `freestanding.ll` counts its free blocks' bytes, headers included, as
  blocks are taken and freed. The bytes it counts are what its bins hold,
  so the count is exact for its heap, whatever pages `l0_heap_release`
  has handed a process's kernel, since those are still the heap's.
- -3 on an operating system, whose `malloc` has no fixed size. 9.2 gains
  "a heap of its own" among what a host may lack.
- Under `L0_RC_CHECK` a freed block is never reused, so it is not
  counted.

---

## Idle CPUs halt (roadmap 0123)

**Changed:** on the aarch64 boards, a CPU with nothing to do, another CPU
whose ring is empty or CPU 0 in `cpu_wait`, polls for 100 microseconds
and then says it sleeps and waits by `wfi`, instead of by `wfe` for
ever. The CPU that hands it a thread, or gives CPU 0 one back, sends a
sleeping CPU the GIC's SGI 0. Section 6.18's "no interrupt sent between
the CPUs" is now "between CPUs that are busy". Nothing a program can
call changed.

*Why:* L0S's `probes/smp/REQUEST-idle-cpus.md`. With 0121 its kernel
runs processes on every CPU, but on QEMU four CPUs made its e2e case
`rootboot_tmpfs` take 222 s against one CPU's 47 s, 204 s of it in the
host's kernel, so it booted everything with one CPU. QEMU's TCG runs
`wfe` as a yield through its main loop, which takes its global lock: an
idle vCPU spun on that lock thousands of times a second, and the vCPU
with work waited for it at every device access. A vCPU in `wfi` QEMU
halts until an interrupt is pending, masked or not.

*Decided:*

- Poll first, then sleep, so a CPU busy with threads, or briefly between
  them, costs no interrupt, which is what 0121 chose rings for. The
  poll is a plain loop of loads and counter reads, neither of which
  takes QEMU's lock.
- 100 microseconds of polling, the request's "a few microseconds" with
  room for QEMU's slower turns between a trap and the next thread. A
  millisecond measured the same (L0S's `rootboot_tmpfs` on four CPUs:
  98 s at 100 µs, 100 s at 1 ms), so the length is not what is left of
  the cost.
- The sleeper stores its flag and then reads the ring; the waker stores
  the ring's count and then reads the flag, both sequentially
  consistent, so at least one sees the other's store: either the
  sleeper finds its work, or the waker sends the SGI, which, pending,
  ends a `wfi` begun after it. A spare SGI, sent to a CPU that woke on
  its own, only ends one later `wfi` early.
- The SGI is taken and ended by the GIC's driver itself, wherever it is
  signalled, and given as spurious, which every caller already handles:
  a thread an SGI interrupts runs on, and `interrupt_wait` waits on.
  No program number names it, so section 6.14's table is unchanged.
- `cpu_wait` reads `GICC_IAR` only when `ISR_EL1` says an interrupt is
  pending: the read is a device access, which on QEMU takes the lock,
  and it was made on every turn of the old loop.
- Each CPU learns its GIC CPU interface from its banked
  `GICD_ITARGETSR0`, rather than assuming it is its number, since PSCI
  and the device tree number CPUs by affinity and the GIC by interface.
- `wfe`, `sev`, and the counter's event stream, which only ended a
  `wfe`, are gone from the runtime.

*Measured:* L0S's `rootboot_tmpfs`, without its 60 s limit, on four CPUs
went from 222 s (204 s of it in the host's kernel) to 98 s (15 s); on two
from 113 s to 96 s; on one it is unchanged, 48 s. So the lock is no longer
the cost, but four CPUs are still twice as slow as one there. A call
handed to CPU 1 and back costs 7.9 µs against `user_run`'s 1.5 µs, too
little to account for it at that case's tens of thousands of calls;
`space_map` and `space_unmap` of a page together cost 11.1 µs under
`-smp 4` against 1.6 µs under one CPU, since QEMU stops every vCPU for an
inner-shareable TLB invalidation, and `space_write` 1.07 µs against
0.55 µs. Which of these, or the kernel's own work, the rest is, L0S has
not yet said.

*Not decided:* `cpu_wait` still gives back a trap before it takes an
interrupt, which the request leaves out on purpose.

---

## Threads run on the other CPUs (roadmap 0121)

**Added:** section 6.18, four builtins: `(cpu_count)`, `(cpu_run c s ctx
deadline tag)`, `(cpu_trapped)`, and `(cpu_wait)`, and two runtime errors,
`not a CPU` and `space still running`. The program still runs on CPU 0
alone; the others run user threads it hands them, each until it traps or
its deadline passes on that CPU's own timer, and hand them back. The
aarch64 boards start the CPUs their device tree lists by PSCI's `CPU_ON`
(QEMU's with `-smp N`, given through `L0_QEMU_ARGS`, and the Pi 5's
four); every other host has one.

*Why:* L0S's `probes/smp/REQUEST-multiple-cpus.md`. L0S runs a
compositor, a terminal, a shell, its drivers, and its file system on one
core, while the Pi 5's other three sit in BL31. Its `want.l0`, CPU 0's
loop that drains every trap the other CPUs posted, hands each thread that
may go on back to a CPU, and fills every CPU from one ready queue, could
not be written: no builtin starts a CPU, `user_run` runs one thread at a
time on the CPU that calls it, and a second CPU could not run L0 code,
since the heap and its reference counts serve one CPU and L0 has no
atomics.

*Decided:* the request's shape, which breaks nothing a program can see:
no value is ever on another CPU, since the runtime copies a context in
and out, so section 8's guarantee and the heap's single owner stand.
Rings in memory rather than inter-processor interrupts, so that a system
call costs no interrupt on either side and CPU 0 takes traps in batches.
Where it chose:

- `cpu_run` reads its context without consuming it. It copies the words
  into the ring anyway, so consuming would buy nothing, and `want.l0`
  hands one context to the next CPU when a ring is full, which a consumed
  one would make a copy for.
- A `c` that is not another CPU is the runtime error `not a CPU`, and
  there is no -3. The request asked for -3 where there is no user mode,
  but such a host has one CPU, so no `c` is valid there, and a kernel
  reads `cpu_count` first, as it reads `space_new`'s -3. One error for
  every host keeps the order of checks one list.
- `space_free` is refused while a thread of the space is handed over and
  not yet taken back by `cpu_trapped`, not merely while it runs: only
  CPU 0's count of what it handed and took is exact without asking the
  other CPU, and a kernel knows that count too.
- A CPU's run ring and trap ring are one ring of 4 slots with three
  counters, handed, run, and taken, each written by one CPU: a slot is
  written by CPU 0, run in place by its CPU, and read back by CPU 0, so a
  context is copied twice in all, and a CPU's traps come back in the order
  its threads were handed, as the request asks.
- `cpu_wait` polls the rings and the GIC, with `wfe` between: the CPU
  that posts sends `sev`, and the generic timer's event stream bounds the
  wait for an interrupt, since whether a masked interrupt ends `wfe` is
  not something the runtime should depend on. QEMU's `wfe` does not sleep,
  so on QEMU an idle CPU spins; on a board it sleeps.
- No `L0_SMP`: `L0_QEMU_ARGS="-smp 4"` already reaches QEMU, and a test's
  `.qemu` file gives the same.
- The riscv64 virt board starts no other hart yet, so has one CPU, which
  section 6.18 allows. Starting them is SBI's `hart_start`, and its
  timer is the SBI's, per hart; nothing here can run that board's QEMU, so
  it waits for a request that needs it.

*Not decided:* a kernel on every CPU, interrupts between CPUs, stopping a
thread on another CPU early, and devices' interrupts on other CPUs, which
the request leaves out on purpose.

---

## The Raspberry Pi 5's dma40 channel 6 is a region, with its interrupt (roadmap 0122)

**New:** on the Pi 5, channel 6 of `dma40`, the BCM2712's 40-bit DMA
controller, is a region (spec 10.3), 0x1000010600 and 0x100 bytes, in the
boot map's block 64, and its interrupt, the GIC's SPI 86, is interrupt
118, level. From `bcm2712-ds.dtsi` (rpi-6.12.y), node `dma40: dma@10600`.

*Why:* L0S asked (its `probes/audio/REQUEST-pi5-dma40.md`), to play sound
on HDMI0. The regions of 0120 already reach every audio register, the MAI
in the HD block and the packet, clock-regeneration and infoframe
registers in HDMI0's run, but nothing could write `MAI_DATA` without the
CPU. The FIFO holds well under a millisecond of sound and the MAI raises
no interrupt, so a CPU feeding it from a process underruns whenever
another process has a 10 ms slice. With DMA the CPU refills a page every
10 ms or so.

*Decided:* one channel, as asked first, not channels 6 to 10: one is what
a driver uses, and more is a later request. Channel 6 because the device
tree gives Linux 6 to 10 and keeps 11 for the firmware's VCHIQ, so 6 is
none of the firmware's. Its interrupt is offered, unlike 0120's, because a
driver that sleeps between periods is the point of the channel. No
deliberate restriction is broken: a channel can write any memory, but so
can the HVS through `iommu4`, and on a board only a program trusted with
devices opens a region. No emulator has this board; the region is checked
by building, and a first run is the user's.

---

## The Raspberry Pi 5's HDMI0 mode set is regions (roadmap 0120)

**New:** four more devices on the Pi 5 are regions (spec 10.3), all in the
boot map's block 65: HDMI0's blocks in one run, 0x107C700000 and 0x4800
bytes (DVP controller, CSC, DVP, HDMI core, PHY, rate manager, packet RAM,
metadata); the HD block, 0x107C720000, 0x100; pixel valve 0, 0x107C410000,
0x100; and DDC0, 0x107D508200, 0x58. Addresses are from `bcm2712.dtsi`
(rpi-6.12.y).

*Why:* L0S asked (its `probes/display/REQUEST-pi5-hdmi-mode.md`). Its `hvs`
driver took the mode the firmware leaves, always 1920x1080, and a 4K
monitor's EDID prefers 3840x2160 at 60 Hz. The one workaround, the
firmware's `SET_TIMING` over the mailbox, re-times HDMI0 but leaves the
firmware rewriting the HVS channel's display list pointers every frame, so
the pointer flickers and lists show stale. A mode set of its own, in
Linux's `vc4` order, never leaves the firmware that state.

*Decided:* one run for HDMI0's blocks, as asked, not seven: they are one
SoC peripheral window, and the driver gains nothing from finer grain. The
hotplug and DDC interrupts (`aon_intr`, `bsc_irq`) are not offered; polling
DDC is enough at first, and a monitor plugged in after boot is a later
request. The clocks stay the firmware's, over the mailbox. No deliberate
restriction is broken: they are devices reached through registers, like
the HVS. No emulator has this board; the regions are checked by building,
and a first run is the user's.

---

## A program can restart its board (roadmap 0119)

**Added:** `(board_reset)` (spec 6.12), an int builtin of no arguments.
It restarts the board, never returning, after standard output and error
are delivered, or returns -3 where the host has no board to restart. The
Raspberry Pi 5 and the aarch64 virt board do it by PSCI's `SYSTEM_RESET`
by SMC; the riscv64 virt board, an operating system, and a process of a
kernel give -3. The aarch64 virt board is now run with `-no-reboot`, so
that a restart ends QEMU with status 0 and a test can see it.

*Why:* L0S's `probes/driver/REQUEST-pi5-reboot.md`. Every test boot on its
Pi 5 needed a person to pull the power, because `exit` halts the board
(`SYSTEM_OFF` is a watchdog reset that tells the bootloader to stop, by
partition 63) and nothing in L0 could start it again. TF-A's Raspberry Pi
platform makes `SYSTEM_RESET` the same watchdog reset without that
partition, so the bootloader boots as at power-on, over the network.

*Decided:* a builtin, not an exit status and not the power manager as a
region. A status that means reset would mix a program's answer with what
the board does after it, and section 10.3 already gives every nonzero
status one meaning. A region of the power manager would also give a
program the board's power domains, which a wrong write switches off, and
would be a Pi-only path with nothing to test on QEMU; it may still come
as its own request, for the watchdog. The builtin returns -3 rather than
being refused on hosts without a board, as `frame_new` does, so a program
can try it and fall back to `exit`.

*Not decided:* the riscv64 virt board, whose reset would be SBI's system
reset extension; nothing asks for it.

---

## The Raspberry Pi 5 gives PCIe's MSIs, RP1's among them (roadmap 0116)

**Added:** spec 10.3's interrupt table for the Pi 5 gains 160 to 223,
`mip0`'s 64 vectors, edge-triggered: a function behind RP1's PCIe
controller that writes n to the bus address 0xFF_FFFFF000 raises
interrupt 160 + n. The host sets the path up as it starts: the
controller's third inbound window, which the firmware leaves empty, from
that address to `mip0` at 0x1000130000, and `mip0`'s vectors
edge-triggered and masked for the VideoCore. RP1's region grows from 4 MB
to 0x414000 bytes, so that its BAR2 and BAR0, the latter holding its
MSI-X table, are in it once a program puts them at PCI 0x400000 and
0x410000.

*Why:* a driver for any of RP1's devices could reach their registers
since 0114 but could only poll, as L0S's USB stack does on the Pi; the
aarch64 virt board's PCIe interrupts came in 0106, and the Pi's are
another path. Two probes on a 2 GB board settled it. As the firmware
leaves them, `mip0`'s registers are all 0 (level, every vector open to
both the CPU and the VideoCore), the controller's inbound windows map
PCI 0 to 64 GB onto RAM one to one and nothing to `mip0`, its own MSI
target is enabled at 0xF_FFFFFFFC, and RP1's MSI-X capability, at 0xB0,
has 61 vectors, off, its table in BAR0 (16 KB) at PCI 0x80410000, beyond
the region. With the window and `mip0` set as Raspberry Pi's Linux sets
them (`pcie-brcmstb.c`, `irq-bcm2712-mip.c`), a write by the CPU of 0 to
`mip0` was taken as interrupt 160, and RP1's vector 0, its table entry
given the doorbell and 1, raised by its `MSIX_CFG` test bit, as 161.

*Decided:* the inbound window and `mip0` are the host's, as the GIC is,
not a driver's: a write to `mip0` raises any vector, so a region of it
would let any program fake any device's interrupt, and the window is one
setting every driver needs alike. The rest of RP1's path, its MSI-X table
and its `MSIX_CFG` registers, is the driver's, through regions it has
already, since which of RP1's 61 sources a driver wants and which number
it gives each are its own. The controller's four INTx lines, which RP1's
pin 1 would use, and the controller's own MSI target, whose one SPI 32
vectors share, are left out: nothing has needed them, and neither was
run. Two board tests show the path: `msi` raises RP1's vector 0 by its
test bit, and `gpio_irq` by RP1's GPIO bank, a level source, GPIO 27's
level-low detector given an unconnected pin, taken as 162 and
acknowledged by `MSIX_CFG`'s IACK. A first try at the latter overrode
the pin's input from low to high and got nothing: the bank's detectors
watch the pad, not the overridden input.

---

## The Pi 5's firmware keeps its framebuffer out of /memory (roadmap 0118)

**Decided:** no change. The frame pool still reads only `/memory` and
leaves out what lies below the image, as spec 10.3 says, and does not
read `/memreserve/` or `/reserved-memory`.

*Why:* L0S asked for those to be read, taking the firmware's HDMI
framebuffer at 0x3F800000 to be in the pool on a Pi 5. The device tree as
the firmware hands it over, dumped on a 2 GB board with a monitor on
HDMI0, says otherwise: `/memory` there is 0 to 0x3F800000 and 0x40000000 to
0x80000000, the framebuffer's 4 MB and the VideoCore's memory above it
left out by the firmware, where with no monitor the first range runs to
0x3FC00000. Its header has no `/memreserve/` entries and the tree no
`simple-framebuffer`; its `/reserved-memory` is BL31's pages below the
image, a `reusable` CMA pool, and the bootloader's config at 0x3FD23180,
outside `/memory`; and a root property `memreserve` names 0x3F800000 to
0x40000000, also outside. The pool at boot was 1,022 pages smaller than
without a monitor. Reading the reservations would leave out nothing more
on this board, and a change is earned by code it makes possible: if a
board or firmware puts a reservation inside `/memory`, that is the
evidence for it.

---

## The Pi 5's HVS answers only with a monitor on HDMI0

**Corrected:** spec 10.3 no longer says `hdmi_force_hotplug=1` has the
firmware leave the HVS scanning out with no monitor. It says the HVS is
readable when a monitor was on HDMI0 at boot, and that a read hangs the
board otherwise.

*Evidence*, roadmap 0110, a 2 GB Pi 5 through `tools/pi5-run`,
`tmp/0110/hvs.l0` reading the HVS's first eight registers and display list
words: with no monitor, `config.txt` saying `hdmi_force_hotplug=1`, the
firmware logged `Select resolution HDMI0/2 hotplug 0` and `HDMI0: Unable
to read EDID block 0`, and the first read, at 0x107C580000, hung the board
with nothing printed and no reset. With a monitor on HDMI0 the log said
`hotplug 1` and the same program printed all sixteen words, the first
0x00002454, and display list words such as 0x80000000 and 0x07EBFC00.

*Not decided:* why. An unclocked block that stalls the bus is the likely
reading, not shown. `l0 card` still writes `hdmi_force_hotplug=1`; this run
shows only that it is not enough for the HVS.

---

## RP1's window answers once the controller is set (roadmap 0114)

**Corrected:** spec 10.3 on the Pi 5 says what is behind the `0xDEADDEAD`
in RP1's window, where the previous entry left it open: the firmware does
not leave the window and RP1's BAR where the device tree's ranges, and the
region, put them.

*Evidence*, `tmp/0114`, a 2 GB Pi 5, through the controller's region and the
2711 driver's registers (`EXT_CFG_INDEX` 0x9000, `EXT_CFG_DATA` 0x8000): the
root port is 14e4:2712 with bus numbers 0, and with them every read behind
it was `ffffffff`. Set to 0, 1, 1, bus 1 device 0 was 1de4:0001, RP1, with
memory space and bus master on, BAR0 0x80410000 and BAR1 0x80000000. The
outbound window registers, by the Linux driver's names, read PCI
0x80000000 from CPU 0x1C_00000000 for 1 GB, so RP1 would have answered at
0x1C00000000, which no region covers. Moving RP1's BAR1 to 0 alone left
the window `deaddead`; also setting the window's CPU high words, 0x4080 and
0x4084, to 0x1F and its PCI address, 0x400C, to 0, made 0x1F00000000 read
0x20001927 and 0x00000002, the chip ID the firmware's log gives and a
platform word.

*Decided:* the region stays at 0x1F00000000, the device tree's, and the
spec says what a driver sets, rather than the board's part setting it: a
region is an address range, and the host sets nothing of PCIe up. The
register offsets are the 2711's and now seen to work on the bcm2712 for
these registers.

---

## The Raspberry Pi 5's PCIe controller for RP1 is a region

**New:** on the Raspberry Pi 5, the PCIe controller RP1 is behind,
`brcm,bcm2712-pcie` at 0x1000120000, 0x9310 bytes, is a region (spec
10.3), in the boot map's block 64 with the IOMMUs, Device-nGnRnE. The spec
no longer says RP1's window holds while the firmware leaves the link set
up; it says what a first run read there.

*Why:* 0102 made RP1's peripheral window a region, 0x1F00000000, on the
plan that `pciex4_reset=0` leaves it answering, and asked a first run to
read each USB controller's xHCI and DWC3 identity. Run on a 2 GB Pi 5
through `tools/pi5-run`, `tmp/0110/rp1usb.l0` opened both controllers over
64 KB and read the first word of each and GSNPSID at 0xC120: all four were
0xDEADDEAD, and so were the window's first two words, where the firmware's
log gives RP1's chip ID, 0x20001927. No read faulted. The window answers,
not as RP1: it is the controller's outbound PCI memory space (the device
tree's `ranges` map PCI address 0 to 0x1F00000000), and RP1 is in it only
once the controller's outbound window is set and RP1's BAR1 assigned. That
is done through the controller's registers, which were no region, so no
program could read the link's state, set the window, or assign the BAR:
L0S's `probes/usb` could not reach its controllers however it was written.

*Decided:* the controller as one region over its whole register block,
0x9310 bytes, the device tree's, as the HVS was, and not the few registers
a first driver needs, since which they are is the driver's to find and the
blocks a region may cover are the board's devices. Configuration space of
RP1 is reached through the controller's index and data registers inside it,
so it needs no region of its own. A first read of the controller
through `tools/pi5-run` (`tmp/0113/pcie.l0`) gave MISC_PCIE_STATUS (0x4068)
0x3E0B0, with the port, data-link-active and PHY-link-up bits set as the
2711 driver names them, MISC_PCIE_CTRL (0x4064) 4, and MISC_REVISION
(0x406C) 0x500: the link is up, and RP1's window still reads 0xDEADDEAD, so
the failing step is above the link, in the outbound window or RP1's BAR.
The offsets are the 2711 driver's, not verified for the bcm2712. Nothing
else is promised: what a driver must set to make RP1 answer is for it to
find.

---

## The Raspberry Pi 5's firmware puts its arguments first

**New:** a board's host gives the program the boot arguments after the
last that is `--l0-args`, and all of them if there is none (spec 10.3).
`l0 card` writes `--l0-args` first in `cmdline.txt`, so on the Pi a
program's arguments are exactly those it gave `l0 card`, however many the
firmware adds. The marker is never one of the arguments, and neither is
any before it. Nothing else changes: QEMU's boards, whose `-append` has no
marker, give every argument, as they did.

*Why:* the first run on a Pi 5 (roadmap 0110, `tmp/0110/basics.l0`, with
`cmdline.txt` holding `first base=0x09000000 a:b`) printed an `arg_count`
of 20: `reboot=w`, `coherent_pool=1M`, `8250.nr_uarts=1`, `pci=pcie_bus_safe`,
and 13 more of the firmware's, then `first`, `base=0x09000000`, and
`a:b`. The spec said the firmware "may follow" `cmdline.txt` with its own;
it puts them before. A program reading `(arg 0)` got `reboot=w`, and its
count was the program's plus 17, which the firmware, its EEPROM, and the
board's model decide. 0098's list of what a first run must check had asked
what the firmware appends; this is the answer, and the reverse of the
guess.

*Decided:* a marker, of three ways. The host dropping the arguments it
knows the firmware adds would be wrong on the next firmware, and a Pi
whose firmware adds one more would give a program an argument that is not
its. Saying the arguments are the firmware's and the program's together
would leave every program, and L0S's kernel above all, to tell them apart
by guessing, with a count that changes under it. The marker needs only the
firmware's order, which it keeps: `cmdline.txt` is copied whole, after its
own. It is `--l0-args`, one token with no space, as every argument is. A
program given the marker as an argument itself, on `l0 card` or on a QEMU
board, gets only what follows it, which is the rule and the cost: such an
argument cannot be passed. The last marker wins, so a firmware that adds
the marker itself, which none does, would not hide the program's. The rule is in the board host every bare board
shares, not the Pi's part, so one rule serves the three and
`tests/virt/boot_args_marker` runs it on QEMU's boards, where a firmware's
arguments can be made up with `-append`. It is not a process's rule: a
process's kernel gives its arguments, and has no firmware's to tell apart.

---

## The Pi 5's debug UART has no identification registers

**New:** spec 10.3 says the Raspberry Pi 5's debug UART is as the firmware
leaves it, enabled with transmit and receive on, and that its PrimeCell
and peripheral identification registers read 0, so a driver does not
probe by them. No code of the language or the runtime changed.

*Why:* 0098 planned the UART's region as 0x1000 bytes so that the
PL011's identification registers were reachable, and `tests/virt/pi5/
uart.l0` expected 0x11 and 0xb1 from two of them, as QEMU gives. The
first run on a Pi 5 (serial 1b08af2e, EEPROM 2026/05/26, booted by TFTP)
printed `hi from the pi`, then 0 and 0. A probe, `roadmap/0109`, read
all eight of them as 32-bit words: every one was 0. The same probe read
FR 0x90, IBRD 0x18, FBRD 0, LCRH 0x70, CR 0x301, and IMSC 0.

*Decided:* the region stays 0x1000, since the registers a driver uses
are inside it and the size is the device tree's. The test expects what
the board does, and its header says the expectation is from a run on a
board, not from the PL011's specification. It also reads the control
register's enable bits, which the firmware's setting makes 0x101 here,
since they are what makes standard output work. The control register's
other bits, and the baud divisors, are the firmware's to change, so the
test does not pin them. `uart.out` was changed by hand, not with
`--bless`, which cannot run a board.

---

## Bytes are sliced and joined without a list

**New:** `(bytes_slice b i j)` is bytes `i` up to `j` of `b` as bytes of
their own, under `write_bytes`'s bounds rule, and `(bytes_concat bs)` is
the bytes of each value of a `(list bytes)`, in order, as one (spec 6.6).
Both read their arguments without consuming them and return new bytes, so
a parameter they read stays read-only (10.3).

*Why:* L0S asked (its `probes/bytes/REQUEST-bytes-slice-join.md`). A
bytes value could be made only by `bytes_from_list`, a read, or a
receive, so wherever a header and a body had to become one message, the
body went through a list, a cons cell a byte, and back: a spawn's header
in front of a program image of hundreds of KB, and the kernel's writes,
fs replies, inet packets, and NIC frames, up to 4 KB each, on every
message. Joining a 6-byte header to a 512 KB image that way took L0S 4.4
to 4.9 ms on the host, and built half a million cells. L0S already reads
in place with (bytes, start, end) and sends ranges wherever it can; what
was left needs one value holding both. `roadmap/0107/why.l0` is the code.

*Decided:* both, as asked: a slice alone would take the lists out of
reading, but not out of building a message. A join over a list rather
than of two values, so a message of many parts is copied once, not once
per part; a builder would have needed a mutable or linear value, which L0
has no other use for. Both copy: a slice that shared its source's block
would keep a whole message alive for its smallest part, and would make
bytes a view, which every builtin reading them would then have to know.
They borrow, as `write_bytes` does, because what they return holds no
part of an argument, and a program that slices a message it keeps
reading should not pay a reference to do so. `bytes_concat` takes a list
of bytes rather than a list of lists, since its parts are already bytes:
the list is a few cells, not one a byte. Nothing is lost: bytes stay
immutable.

---

## l0 test starts fewer processes, and runs tests side by side

**No semantic change. L0 is exactly the language it was before this entry.**
`l0 test -j N`, or `L0_JOBS=N`, runs up to N tests at once and writes
their TAP lines in the tests' order, each as soon as every test before it
is done. By default it is 1 on this host and the CPU count on the board.
The driver also stops starting helpers whose answer it already has: it
looks for a leak report only when a test wrote something on standard
error, for `(blessed` only under `--bless`, which alone writes it, and
measures a bundle's files with one `wc`, not a `wc` and a `tr` each.
What `l0 check` and `l0 test` print is unchanged.

**Why.** L0S asked (its `probes/driver/REQUEST-fewer-processes.md`). Its
`make test`, 127 runs of `l0 test` and 4,584 tests, took 7 minutes 20
seconds for 3 minutes of CPU on a Mac whose endpoint security agent vets
every program launch, about 15 ms each and barely overlapping. Each
passing test started three helpers, about 80 ms of them, beside its own 25
ms. On the board, each test is a QEMU boot, mostly CPU, which ran one at a
time on one core. Here, io_test's 49 tests go from 7.96 s to 2.49 s, and
map_test's 20 on the aarch64 board from 5.31 s to 3.54 s at `-j 1` and
1.92 s at the default of 14.

**Decided.** One on this host unless asked, because tests there run in
the directory `l0 test` runs in and may write the same file, which one at
a time never showed; the board has no files, so its tests cannot collide.
`-j` sets a window rather than a pool: before a test starts, the oldest
still running is waited for and judged, which keeps the output in order
and streaming at the cost of an idle slot behind a slow test. Left out of
L0S's four: running a file's tests in one process, which would move
`lib/test.l0`'s `--bless` argument and need the driver to split one
process's output by test, and rerun tests to blame a leak; worth
measuring after these.

---

## The aarch64 virt board gives PCIe's interrupts, INTx and MSI

**New:** on the aarch64 virt board, the host bridge's four INTx lines,
INTA to INTD, are interrupts 35 to 38, the GIC's own numbers, and the
GICv2m frame's 64 MSI SPIs are 80 to 143 (spec 10.3). A function raises
an MSI by writing its number to 0x08020040, the frame's
`MSI_SETSPI_NS`, which its driver writes into the function's MSI
capability through the ECAM; the frame stays the host's. The host makes
an MSI edge-triggered as it enables it, in `GICD_ICFGR`; INTx stays
level, as the PL011's is.

*Why:* L0S asked (its `probes/usb/REQUEST-pcie-interrupts.md`, whose
`irq_virt_test.l0` got -3 for all six of 35 to 38, 80, and 143). Its
`xhci` and `sdhci` drivers, on `qemu-xhci` and `sdhci-pci`, were the last
of its demo's drivers that could not wait for their device: `xhci` woke
1,000 times a second, for ever, to read its event ring. Every other
driver there waits on `irq_bind`. No program can work around it: only the
host decides what is an interrupt.

*Decided:* both routes at once, as asked. INTx is what every function
has and the least a driver must set up; but four lines serve every slot,
and in the L0S kernel an interrupt is bound to one port, so two
functions sharing a line cannot both be driven by it. MSI gives each its
own. The MSI range is fixed, as QEMU fixes it, rather than read from
`MSI_TYPER` at boot, as every other number in the table is fixed; they
agree. The address is in the spec, so a driver need not know the frame.
Edge for the MSIs because the frame pulses its SPI: a level
configuration happens to latch the pulse in QEMU's GIC, but on a GIC
that follows the architecture it would be lost. Left for later: the Pi
5's PCIe interrupts, which reach its GIC through bcm2712's MIP, and the
riscv64 board's INTx, the PLIC's 32 to 35, until something there drives
PCIe. `tests/virt/aarch64/pcie_irq` drives QEMU's `edu` device, which
raises either on a write, and takes one of each.

---

## A board program sizes its heap and stack, or brings its own layout

**New:** a board's layout, `runtime/board/BOARD.ld`, is a template that
`l0 build` fills with a heap size and a stack size (spec 10.3), today's
by default, which `--heap-mb N` and `--stack-mb N` set for `--target
virt` and `pi5`; the heap's start and the stack's top stay where they
were. `--layout FILE` links with a script of the program's own in place
of the template, which must define the template's symbols and keep
standard input where the template has it; the driver puts the sizes
before either script and its checks after. Each manifest gives its
board's defaults and room, `T_HEAP_MB`, `T_STACK_MB`, and `T_ROOM_MB`.

**Changed:** the frame windows are no longer the gaps between a layout's
parts, but the RAM a board's boot map reaches, from which `board.ll`
cuts everything below the image's end, the heap, and the stack, as it
already cut the device tree and standard input. With the default sizes
the pool is what it was.

*Why:* L0S asked, in its proposal "Kernel-Sized Board Layouts", and so
did the user, for a microkernel; it is 0097's item 2. A kernel is an
ordinary board program, so it got a program's layout: on the aarch64
virt board at 2 GB a heap of 1,024 MB and a stack of 256 MB, and 765 MB
of frames for all its processes. L0S measured its demo with 65 processes
at a kernel heap of 20.5 MB, a stack under 8 KB, and 30 MB of frames.
With a heap of 64 MB and a stack of 16 MB the pool is about 1,967 MB.

*Decided:* sizes, not addresses, so that one request means the same on
every board; and options to the driver, not a declaration in the program,
so that an L0 program stays the same on every host (spec 9.2). Both
changes at once, since either alone gains nothing: a smaller heap left
the RAM it gave up in no window, and derived windows with a fixed heap
change nothing below the user range. The heap's start stays fixed above
the loader's standard input, rather than following wherever the input
lies, so that a heap's size never depends on the input's. A layout file
is the user's ask, for a program whose needs are not two sizes; it is
checked only for what the runtime and `l0 boot` rely on, since a board
reports the rest itself. Left for later: a heap that grows from the pool,
which L0S names the version that never needs revisiting; RAM under the
user range, L0S's item 4; RAM past 0xC0000000 on the aarch64 virt board,
which its boot map does not reach; and recording the sizes in the image's
header, so that `l0 boot` could check the board's RAM holds them.

---

## A frame's bytes made to agree between the CPU's caches and memory

**New:** `(frame_sync f dir)` (spec 6.13) makes frame `f`'s bytes agree
between the CPU and a device, and returns 0: with `dir` 1 the CPU's
writes reach memory, for a device about to read; with 2 the CPU's next
reads come from memory, for what a device wrote; with 3 both. It orders
accesses as `barrier` does. It raises `not a frame` as `frame_address`
does, and the new runtime error `sync direction out of range` for any
other `dir`. On the aarch64 hosts it is `dc cvac`, `dc ivac`, or `dc
civac` a line at a time over the frame in the host's map, then `dsb sy`;
on the riscv64 board, `fence iorw, iorw`. Behind it, a host function,
`l0_host_frame_sync(f, dir)` (spec 10.3).

*Why:* L0S asked (its `probes/usb/REQUEST-pcie-rp1-cache.md`, whose
`want.l0` gave `unknown function frame_sync`). The Pi 5's DMA is not
coherent, and the spec said so and left the builtin to "a driver that
needs it". L0S's xHCI driver is that driver: it writes TRBs into a
ring's frame before ringing a doorbell, and reads what the controller
wrote into an event ring's. No L0 code can clean a cache line, and only
the host knows both a frame and where its own map holds it.

*Decided:* a builtin that syncs, not frames mapped non-cacheable. The
host's map of its RAM is cacheable in 1 GB blocks, and mapping a page both
cacheable and not is what the architecture warns against; splitting the
host's map around each such frame would cost more than a cache operation,
and a driver's rings are small and synced only around a transfer. A whole
frame at a time, not a range, since a frame is what a device is given, and
4096 bytes is 64 lines. One builtin with a direction, as the request
proposed, rather than three. On the virt boards it does the same cache
operations as on the Pi, rather than only a barrier, so that the suite
runs the instructions the Pi will; QEMU models no caches, so there they
change nothing. Invalidating may lose a CPU write not synced first, as on
every architecture with this operation: a driver syncs a frame one way at
a time. Nothing has run it on a Pi, as nothing of the Pi 5's has.

---

## The Raspberry Pi 5's HVS and its IOMMU are regions

**New:** on the Raspberry Pi 5, three more devices are regions (spec
10.3): the HVS, 0x107C580000 and 0x1A000 bytes, in the boot map's block
65 with the others; and `iommu4`, 0x1000005200, and `iommuc`, 0x1000005B00,
0x80 bytes each, in block 64, which the boot map now maps as
Device-nGnRnE too. `l0 card`'s `config.txt` says `hdmi_force_hotplug=1`.

*Why:* L0S asked (its `probes/display/REQUEST-pi5-hvs-iommu.md`). Its
`hvs` driver composes the screen as its virtio-gpu driver does on QEMU,
with no pixel copied: a plane per window, read by the HVS straight from
the pages a client shares. Those pages are scattered and a plane reads
one run of addresses, so the driver maps them one after another through
`iommu4`, which the device tree puts in front of the HVS
(`iommus = <&iommu4>`), and whose cache, `iommuc`, it must flush. With
none of them a region, the driver could only say there was no display.

*Decided:* the firmware's display is kept, not brought up by the host:
the firmware has HDMI0 scanning out by the time the program runs, and the
driver takes its mode, so `hdmi_force_hotplug=1` is all that makes that
hold without a monitor's hotplug seen in time. A region over the
framebuffer the mailbox can ask for was the alternative, and was not
taken: it is RAM, so as device memory every pixel written to it is
uncached, and every window and scroll would be copied into it. Contiguous
frames in place of the IOMMU would be a new allocator, and would give a
frame's number a meaning section 6.13 denies it. Block 64 is mapped whole,
as block 65 is, though only the IOMMUs in it are regions: the boot map is
the host's, and a region is still only a range the device table names.
The HVS's interrupts, through `disp_intr`, wait for a request of their
own, since the driver polls. The places are the Raspberry Pi kernel's
`rpi-6.12.y` device tree's, whose `axi` bus maps them unchanged; nothing
of them has run on a board, and `tests/virt/pi5/hvs` is what a first run
shows.

---

## The Raspberry Pi 5's RP1 is a region

**New:** on the Raspberry Pi 5, RP1's peripherals, 0x1F00000000 and
0x400000 bytes, are a region (spec 10.3), in the boot map's block 124,
Device-nGnRnE, which a space's root table copies for the host as it does
every block of the boot map. `l0 card`'s `config.txt` says
`pciex4_reset=0`.

*Why:* L0S asked, in the same request as the virt board's PCIe (its
`probes/usb/REQUEST-pcie-rp1-cache.md`). On the Pi 5, USB is the only way
to attach a keyboard and a mouse, and both USB controllers are DWC3s, so
xHCIs, on RP1, at 0x1F00200000 and 0x1F00300000. The spec said RP1 "is
none", so no driver could reach them.

*Decided:* the firmware sets up the PCIe link to RP1 and the host keeps
it, rather than the host bringing up the root complex itself: the
bootloader already does it, `pciex4_reset=0` tells the firmware to leave
it, and bringing up PCIe would be the host deciding for every driver what
is behind it. Only RP1's peripheral window is given, not the whole of
PCIe's outbound window, since nothing else is behind this link.
RP1's DMA offset, bus 0x1000000000 for CPU 0 (bcm2712's `dma-ranges`),
stays the driver's to add, so that `frame_address` means one thing on
every board. Neither the window nor the offset has been checked on a
board, as nothing of the Pi 5's has; `tests/virt/pi5/rp1` is what a first
run shows.

---

## The aarch64 virt board's PCIe ECAM and MMIO window are regions

**New:** on QEMU's aarch64 virt board, two more devices are regions (spec
10.3): the PCIe ECAM, 0x4010000000 and 0x10000000 bytes, and the 32-bit
MMIO window, 0x10000000 and 0x2EFF0000 bytes. The boot map's block 256,
0x4000000000, which holds the ECAM, is device memory, Device-nGnRnE, as
block 0 is, and so is a space's for the host. The window was in block 0
already, and only the table refused it.

*Why:* L0S asked (its `probes/usb/REQUEST-pcie-rp1-cache.md`). Its USB
stack, for the keyboard and mouse of a Raspberry Pi 5, drives an xHCI,
which QEMU's virt board has only as `qemu-xhci`, on PCIe. Finding it,
sizing its BAR, and turning on its memory space needs the ECAM, and
reaching its registers needs the window; its board test opened bus 0's
megabyte and the window's ends, and all three gave -3. No program can work
around a region the host refuses.

*Decided:* the host sets up nothing of PCIe. Assigning BARs and enabling a
function are a driver's, through the ECAM, as L0S's `pcie` server does; a
host that enumerated would decide where BARs go for every program, and the
board has one driver that cares. The table is fixed, as the other devices
are, rather than read from the device tree's `pcie@10000000` node: the
places are QEMU's with high memory on, which `l0 boot` never turns off, and
the device tree would be the first thing the host read for a region. The
port-I/O window and the 64-bit MMIO window are left out, since a driver
can put every BAR in the 32-bit window, and so are INTx and MSIs, which
L0S's driver does without by polling, until a request of their own. The
riscv64 board is unchanged: nothing has asked for its PCIe.

---

## A call of a generic function has the type its arguments give it

**Fixed:** the emitter typed a call to a function with type parameters from
the copy it calls, whose return type is written in kinds (spec 10.2): a
parameter standing for a counted type is `(list int)`. So what lay inside such
a type was lost at the call. `(wrap_any gs)` with `gs` a `(list Pt)` had the
type `(Option (list int))`, and a list taken out of it had elements the
emitter took for ints. Two failures followed, both from L0S's kernel, which
keeps `(Map int (list ImageSeg))`: `(cons (Pt 3 4) (match (wrap_any gs) ...))`
built its cell with a mask that did not mark the head as counted, so the `Pt`
was never freed (a leak, found by `l0 test`'s leak check), and
`(head hs)` of such a list was not given its reference, so it was freed while
still in use (`use of a freed block`). Neither shows in a program whose
generic calls take or return only the parameter's own type.

A call's type is now `ty_subst` of the generic's return type by what its
arguments' types bind, as the checker computes it. The copy is unchanged, and
so is the output for a call whose result has nothing nested under a
parameter. The spec's 10.2 now says that the call, not the copy, decides.

Evidence: `tests/unit/generic_nested`, from L0S's report
`probes/generic-match-leak`; ten cases, five leaked and one more used a freed
block.

## A region can be closed

**New:** `(region_close r)` (spec 6.12) closes region `r` and returns 0,
after every access to it is complete; its number may be given again, and
`region_open` gives the lowest free one. At most 64 are open at once,
where before 64 could be opened over a program's life. Closing a region
not open is the runtime error `not a region`. Behind it, a host function,
`l0_host_region_close(addr, len)`, and for a process, system call 13,
`unregion(addr, len)` (spec 10.3), which a kernel may ignore, as call 12.
The library's `close_device` closes what `open_device` opened.

*Why:* L0S asked (its `probes/region-close/REQUEST-region-close.md`). Its
compositor opens a region over each window's title bar and frame buffers,
which are shared pages it gives up when the window closes, and the
runtime's table of 64 never gave a slot back: so `wm` could open 30
windows over its whole life, and resizing, which needs buffers of a new
size and so new regions, could not be built at all. Giving the pages up
left the regions open over pages no longer mapped. A program cannot work
around it: only `l0rt.ll` holds the table. L0S's workarounds were to keep
every closed window's buffers at the largest size one could ever be,
about 95 MB a window, or one region over all its device pages, which
loses the check that a draw stays inside its own buffer.

*Decided:* a region closed twice is a runtime error, not a code as
`close`'s -2 is, since every other region builtin raises `not a region`
for a number not open, and a double close is a bug, not a condition to
handle. The table stays at 64: with closing, the limit is how many are
open at once, which is what a fixed table can promise, and `wm` needs 4
plus 2 a window open now. Closing does not resize, since a buffer of a
new size is new pages at a new address anyway.

*Fixed on the way:* when the table was full, `l0_region_open` gave -5
after the host had already mapped the region, so a process's kernel kept
pages for a region no one could reach. It now hands them back by the same
host function before giving -5.

*How:* a free slot is a length of 0, which no open region has; `region_at`
treats one as not a region. On a board, and under `host-libc.ll`, which
gives no regions, the host function does nothing. A process's host makes
call 13; the IR harness kernels answer it as a call they do not know, and
`tests/virt/user/kernel.l0` unmaps the window pages call 10 mapped, and
takes them back when they are the last it gave, which a program that
closes before it opens again always reaches.

---

## A process hands free heap pages back to its kernel

**New:** system call 12, `release(base, len)` (spec 10.3): the whole
pages of the heap in the range hold nothing the process needs, and its
kernel may unmap them and free their frames, a later touch reading zero,
or do nothing. `freestanding.ll`'s `l0_host_free` makes it, through a hook
its host defines, `l0_heap_release`: a process's makes the call, a
board's does nothing.

*Why:* L0S asked (its `l0-request-heap-pages.md`). A kernel may map a
process's heap a page at a time as it is first touched, and L0S's does,
but nothing ever said a page was free again: in a process, 0085's "back
to the host" stops at the allocator over the process's own heap. So a
process held its peak heap until it exited, which costs a short command
nothing and L0S's servers, the compositor, the terminals, the file
system, and the network stack, which run from boot to shutdown, the
board. The kernel cannot tell a free page from a live one, and a program
cannot reach its allocator: the calls from 256 are the program's, not
the runtime's. `tests/virt/user/release`, which holds 32 MiB in an array
and lets it go, saw its kernel 8,212 frames short before and has them
back now.

*How:* the allocator names a page as it comes free, once: the whole pages
of the merged free block that hold none of its words, its first 32 bytes
and last 8, and lie at least in part in the block just freed. So freeing a
small block beside a large free one names a page or two, not the large
one again, and the call is made only where memory leaves the runtime
for the allocator: arrays, bytes, and chunks past the 4 the runtime keeps.
Those 4 and the free lists stay touched, since the runtime cuts from them
next; giving their pages back would trade a call now for a fault per page
soon after. Ignoring the call is allowed, so every kernel that predates it
still runs every program: the IR harness kernels answer it as a call they
do not know, and `tests/virt/user/kernel.l0` unmaps and frees each page,
keeping each page's frame in its map to do so, and gives its count of
frames by a call of its own, 263, for the test to read. The compiler
compiling itself as a process takes the time it did, to the second, under
both kernels on both CPUs.

---

## The Raspberry Pi 5

**What changed.** A third board, `l0 build --target pi5` (spec 10.3): an
aarch64 host for the Raspberry Pi 5 with no operating system beneath it,
made of the parts the virt boards use and four it adds, a board part
`runtime/board/pi5-aarch64.ll` with its layout, `runtime/bare/psci.ll`, and
a manifest. What it changed for every aarch64 board: the boot code accepts
entry at EL2 and leaves it for EL1; the translation is 39 bits of virtual
address and 40 of physical (TCR T0SZ 25, IPS 40 bits) with a 512-entry boot
map, where it was 32 and 32 with 4; the board's part maps the RAM the
device tree describes, through a new hook `l0_board_map_ram`; standard
input is the device tree's initrd where there is one, and the loader's word
where there is none; an arm64 image's reserved word at byte 48 names its
board. `l0 boot` refuses a board it has no emulator for, `l0 card` writes
the SD card's files, and the virt aarch64 board now runs with its
virtualization extension on, so that the whole suite enters at EL2. Roadmap
0098. **Nothing here has run on a Raspberry Pi 5**: QEMU has no such
machine, and the user had none at hand.

**Why.** The user asked for it. The 0088 split was made so that a board
would be a part, a layout, and a manifest, and the Pi 4's GIC-400 and PL011
were the example; the Pi 5 has both too, and four things that QEMU's board
hid: it enters at EL2, behind a firmware that stays resident; its devices
are above 4 GB, outside a 4 GB translation; it has no semihosting and no
loader, so standard error, the exit status, and standard input must come
by the serial line, by PSCI, and by what the firmware loads; and its RAM
starts at 0 and varies from 2 GB to 16, so a boot map cannot assume it.

**The decisions.**

- **EL2.** The Pi's BL31 enters the image at EL2. The boot code checks
  `CurrentEL` and, at EL2, sets `HCR_EL2.RW`, lets EL1 read the counter,
  zeroes the virtual offset, takes the virtualization IDs from the real
  ones, gives `SCTLR_EL1` its reset value, and `eret`s to EL1h. QEMU's
  virt board can enter at EL2 too (`-M virt,virtualization=on`), which the
  aarch64 virt manifest now asks for, so the drop is run by the whole suite
  rather than first by the hardware.
- **Addresses.** One translation for every aarch64 board, 39 bits of
  virtual address as Sv39 on riscv64, a level-1 table of 512 gigabyte
  blocks, whose 4th entry is still the user range, so process images and
  spaces are unchanged. The virt boards' boot map is the Pi's with
  everything past 3 GB empty. The Pi's maps blocks 0 and 1 and the
  devices' at boot, since the stack is in block 1, and the rest of the RAM
  when the host reads `/memory`, a gigabyte at a time and never block 3,
  so that nothing absent is mapped as normal memory, where a speculative
  access could fault the bus.
- **Standard input.** The arm64 boot protocol's own way: the firmware loads
  an `initramfs` and says where in `/chosen` (`linux,initrd-start` and
  `-end`). Both host kinds read it first, so QEMU's `-initrd` is a test of
  it on aarch64, where QEMU puts it below the heap; on riscv64 QEMU puts it
  at 0xA0200000, inside the heap, so it is ignored there and the test is
  aarch64's. The loader's word is the fallback, so the virt boards' manifests are
  unchanged. A board with neither has empty input, never garbage: the Pi's
  layout puts `__input_len` at a word in its image that is always 0. (A
  weak symbol was tried first and dropped: an external symbol's address is
  never 0 to LLVM, so a test for "absent" folds away, and a weak one is
  reached through the GOT, which a raw image has none of.)
- **The serial line.** Standard output and error share the debug UART, as
  the spec has said a board with one line may. The exit status has no
  channel, so a nonzero one is written as `l0: exit status N`, after the
  UART is drained, and the board is powered off by PSCI's `SYSTEM_OFF`
  through SMC, which BL31 answers, and which halts it until the power
  button. The virt boards' PSCI is through HVC, so the call is a part of its
  own, linked only by the Pi.
- **Interrupts.** The debug UART is SPI 121, GIC ID 153, and 152 on the
  later silicon, which the device tree for the stepping a board has would
  say but the host cannot rely on, so it enables both and reports either as
  153. Reading the stepping register for it was dropped, since a wrong
  address is an abort at boot.
- **RAM in the user range.** Left unused, as on riscv64, so the user range
  and every process image stay where they were.
- **DMA.** The Pi's is not coherent, and no device is driven yet that would
  show it. The spec says so rather than promising what it does not give; a
  builtin that cleans and invalidates a frame waits for a driver.
- **Telling images apart.** Both arm64 boards' images carry `ARM\x64`, and
  `l0 boot` would have started a Pi image on QEMU. The header's reserved
  word at byte 48, which the protocol says is zero and neither loader
  reads, now holds a board's tag, 0 for virt and "pi5" for the Pi.
- **The firmware's files.** `l0 card` writes `l0.img`, `cmdline.txt`,
  `input.bin`, and `config.txt` into a directory the user copies to the
  card's boot partition beside the Pi's own files. The device trees and
  firmware are the user's, from Raspberry Pi OS; the toolchain ships none.

**What it costs.** The boot map is 4 KB where it was 32 bytes. Every
aarch64 program now runs with 39-bit translation. A Pi 5 with 1 GB is not
supported: the heap and stack are in the 2nd gigabyte.

**What a first run on a board must check.** UART output at all; that the
drop from EL2 reaches `l0_bare_main`; `/memory` and the firmware's
reservations on 2, 4, 8, and 16 GB boards, since only the 8 GB layout was
read; that BL31's pages inside block 0 are never touched; that `kernel_address`
and the initramfs address are honoured; what the firmware appends to
`cmdline.txt` in `/chosen/bootargs`, which a program would see as extra
arguments; the PSCI halt; the 152 and 153
numbering on each silicon; and that user mode and the interrupts work on a
Cortex-A76.

---

## The virt boards' frames come from all the RAM the layout leaves

**New:** the builtin `frame_free_count`, `-> int` (spec 6.13): how many
pages the host has left for frames and tables, -3 on a host with no user
mode. **Changed:** a virt board's pool of frames is no longer a fixed
range of 98,304 pages but the RAM the device tree's `/memory` nodes
describe within the board's frame windows, less the device tree and
standard input's bytes, which join once a read has reached the last of
them (spec 10.3). Frame numbers are the host's, no longer the pool's
`f`-th page from a fixed base. The spec now says where a board's standard
input is, which it never had.

*Why:* L0S asked (its `l0-request-board-memory.md`, items 1, 3, and 5).
Every process of its kernel lives in frames, and on the aarch64 board the
layout gave them 384 MB of 2 GB, while 250 MB around the image and the
device tree and the 128 MB input window sat idle. The pool now takes those
too, about 765 MB at 2 GB, and on riscv64 the whole 5th gigabyte and the
gaps, about 1.2 GB at 3 GB, up from 384 MB on each. The input window held
L0S's 10.8 MB initramfs, which the program copies into its heap, and no
read can give those bytes again once one has reached their end, so its
pages join then, by themselves, with no builtin to ask: `frame_free_count`
grows by them. Without a count, a kernel learned the pool's size only by
running it dry, and could not refuse a spawn it could not finish
(`roadmap/0097/why.l0`).

*How:* the host builds the pool at boot from up to 32 pieces, each window
cut by `/memory`'s ranges and with the device tree and the input's pages
cut out, and keeps its 4 bytes a page in the pool's first pages, sized from
what it found, so no cap is left; frames are numbered through the pieces,
the input's last, which join on the free list. The input's count is read
once at boot, since its page is in the pool.

*Left:* the heap and stack keep their fixed 1 GB and 256 MB on aarch64,
which a kernel needs far less of; a heap that grows from the pool, or sizes
the program chooses, is L0S's item 2, for an item of its own. RAM past the
windows is not used: at `-m 4G` on aarch64, the RAM under the user range
cannot be the host's identity map, and that past 4 GB needs a boot map wider
than its 4 GB (TCR T0SZ 32), as on riscv64 past 0x140000000. Standard input
kept as frames, so a kernel maps program images from it without a copy
(L0S's item 4), waits for a program that needs the sharing. Firmware
reservations, the device tree's `/memreserve/` and `/reserved-memory`, are
not read: on both boards they lie below the image, outside every window,
and a board whose firmware reserves RAM inside one says so in its windows.

---

## Square root of a float

**New:** the builtin `float_sqrt`, `float -> float` (spec 6.17), IEEE 754's
squareRoot to nearest.

*Why now:* 0094 left it out until a program needed it, and L0S's 4K face
does: curves are flattened into n >= sqrt(bend / 8 tol) lines, a stroke's
unit normal divides by sqrt(dx^2 + dy^2), and an arc's step is about
sqrt(8 tol / r), all over an integer `isqrt` that truncates.

*Why a builtin, not the library:* square root is correctly rounded by IEEE
754 and one instruction on aarch64 (`fsqrt`), riscv64 (`fsqrt.d`), and amd64
(`sqrtsd`), through `llvm.sqrt.f64`, which calls no libm. Newton's method in
L0 is neither correctly rounded without a correction step nor as fast, and
only a correctly rounded one keeps 6.17's promise that every host gives the
same bits. The NaN a negative argument makes is the one NaN, like every
operation's. Absolute value is still left out: one comparison writes it.

---

## The library has sine and cosine, and no language change for it

`float_sin` and `float_cos` are in `lib/prelude.l0`, in L0, since no compiled
program calls C and no board has a libm. L0S's font tool turned a shape only
by 5 degrees from a table of sines in fixed point; it can now turn by any
angle (`roadmap/0094/why.l0` was the program).

They are fdlibm's, as musl has them: reduce by a multiple of pi/2 held in
three parts (Cody-Waite, the medium case of `__rem_pio2`), then `__sin` and
`__cos`'s polynomials on [-pi/4, pi/4], picked by the quadrant. Within 1 ulp
below 2^20 times pi/2, checked against Python's `math` at 5 degree
multiples, quadrant edges, and 40 random arguments, and the same on the host,
both boards, and Linux arm64. Past that, and for an infinity or NaN, the one
NaN: Payne-Hanek needs a table of 2/pi's bits and waits for a program that
passes such an argument. `(float_sin -0.0)` is -0.0.

*Evidence on literals:* the 12 polynomial coefficients, 2/pi, and the 6 parts
of pi/2 each have 18 or 21 significant digits, so their m is past 2^53
and a literal cannot be them. They are written `(float_from_bits N)`, with
N from fdlibm's hex, cross-checked against its decimals in Python. A correctly rounding literal parser would let them be
written as fdlibm prints them; this is one program for it, and not yet
earning it.

---

## Floating point

**New:** the type `float`, float literals such as `0.5`, and the builtins
`float_add float_sub float_mul float_div float_neg`, `float_lt float_le
float_gt float_ge`, `float_from_int float_to_int`, and `float_bits
float_from_bits` (spec 2.1, 3, 6.17, 10.1).

*Why now:* L0S, the kernel's own project, draws its font's circles from a
table of sines in 1/65536 that holds sin of 5k degrees, so a shape turns
only by multiples of 5 degrees. `roadmap/0094/why.l0` is the smallest
program that cannot be written: a point on a circle at any angle. 0028's
json earned floats earlier for printing numbers, and 0055 named them as not
yet earned; text conversion is still not this.

**Names carry the type** (`float_add`, as `bit_` and `array_`), because L0
has no overloading and `add` stays `int`'s. `float` is not reserved, as
`bytes` is not, so no program loses a name.

**The word holds the float's key, not its bits.** A key is the IEEE bits
with bits 0 to 62 flipped when the sign is set, so as signed integers keys
are in IEEE totalOrder, and the map is its own inverse. *Why:* `eq`, `hash`,
and `compare` read non-pointer words as signed integers, and on raw bits
-2.0 would sort above -1.0. With keys they need no change in the compiler or
the runtime, work on any value holding a float, and let a float key the
library's map. The cost is that `eq` is identity of keys, so `(eq 0.0 -0.0)`
is false and NaN is `eq` to itself, while `float_lt` and its siblings are
IEEE's. Rejected: the checker refusing `compare` on any type that mentions
`float`, which would keep floats out of sorted lists and map keys for
nothing.

**NaN is one value.** CPUs disagree on the NaN an operation makes (riscv64
always 0x7FF8000000000000, aarch64 passes a payload on unless FPCR.DN, amd64
0xFFF8000000000000), and under keys that would show in `eq`, `hash`, and
`compare`, so one program would differ by CPU. Every operation that can
make a NaN, and `float_from_bits`, gives 0x7FF8000000000000. `float_neg` of
it is the one other NaN.

**Literals are the ones a single IEEE division gets exactly right.** LLVM IR
accepts a decimal double only if exact, so the compiler writes bits, and it
cannot compute them with floats. Clinger's fast path (m at most 2^53, k at
most 22, both exact) makes m divided by 10^k correctly rounded by IEEE
itself. Anything else is a compile error that names the limit, and
`float_from_bits` writes every other value. No exponent form until a
program needs one.

**`float_to_int` saturates and `float_div` does not trap.** NaN gives 0 and
an out-of-range value gives the end of the range, never poison, as `add`
never traps. Rounding is always to nearest, ties to even.

**A literal is its own expression, not a call.** Desugaring `0.1` to a call
of `float_div` would let a program's own function of that name take it over
(0031), so the lexer computes the bits of m and of 10^k with integers and
the emitter writes `fdiv double` of the two. The 2^53 and 22-digit limits
are the lexer's errors.

**Cost.** Each operation decodes and encodes the key, and the NaN select
follows. A dependent chain of one multiply and one add took 9.8 ns an
iteration at `-O2`, against 1.3 ns for an int chain, on the host. That
was not measured against raw bits, so how much of it is the key is not
known; the answer is in roadmap 0094's Log, to be revisited if a program's
hot loop is float arithmetic.

**Left out:** `float_sqrt`, `float_abs`, `float_floor` (amd64 calls libm for
it, which the runtime may not), exponent literals, and text conversion.
`float_sin` and `float_cos` are the library's, roadmap 0095.

---

## A process's image is an ELF, its segments mapped by their permissions

**No change to what a program means.** What changes is the image `l0
build --target proc` writes and what a kernel does with it (section
10.3). The image was a process's bytes from 0xC0000000, raw, at most
4 MB, which a kernel mapped as one range, and the heap began at
0xC0400000 whatever the image's size. It is now a static ELF64 with at
most three `PT_LOAD` segments: code, readable and executable; rodata,
readable; and data with the bss, readable and writable. The kernel maps
each segment with at least its permissions and starts the process at
`e_entry`. The heap starts at the first page after the image, and the
image must end below 0xD0000000. `--target virt` stays raw, as its boot
protocols need. Roadmap 0093; the toolchain and this repository's three
kernels follow it there.

**Why.** L0S, the kernel's own project, asked for it. A raw image tells
its kernel nothing, and that cost three things. A kernel cannot tell
where the bss ends, so the layout fixed the heap at 0xC0400000 and capped
the image at 4 MB. The compiler, the largest program here, is 1.4 MB raw;
L0S expects an interpreter to approach the cap. A kernel cannot tell code
from data, so it maps every page writable and executable:
`tests/virt/user/kernel.l0` maps every page from 0xC0000000 with `perm` 3,
so a process that writes over its own code is not stopped. And nothing
in the image says which CPU it is for, or names a function at a fault's
address. 0082's entry, "A process's image is raw, as its kernel loads
it", named the reason to bring the ELF back: a kernel that maps code read-only and data never executable. L0S's
is one, and the L0 kernel here becomes one with this change, since
`space_map` already takes a `perm` (6.13).

0082's reason for raw does not come back. It wrote raw because flattening
an ELF took `llvm-objcopy`, which an installed toolchain has no name for.
`ld.lld` writes the ELF itself, and the driver only stops flattening it.
What the toolchain writes for a target is still what that target's loader
loads; a process's loader now wants the segments.

**The decisions.**

- *A strict subset of ELF, listed in 10.3*, so a kernel loads an image
  knowing only that list. The image is `ET_EXEC` and static: no
  interpreter, dynamic section, TLS, or relocation. Each segment's offset
  and address are multiples of 4096, so a kernel copies whole pages. The
  headers lie in no segment, so no page of the process holds them. The
  section table and symbols may stay, for a kernel or a person naming a
  fault's address, and a kernel ignores them.
- *Three segments, and none both writable and executable,* which is what
  a kernel needs to map code read and execute, rodata read only, and data
  read and write. It also lets a kernel later share one copy of a
  program's read-only pages between every process running it.
- *A kernel gives at least each segment's permissions, and may give
  more.* The program's side is the promise: it writes no page of its code
  or rodata, and executes none of its data, heap, or stack. So a kernel
  that maps everything writable and executable still runs every program.
  The IR harness does, mapping each process's slot in 2 MB blocks. A
  kernel that enforces the flags, as the L0 kernel will, ends a process
  that breaks them, by the fault it takes.
- *The heap starts at the first page after the image,* the highest
  `p_vaddr` plus `p_memsz`. So a kernel learns it from the headers, and
  nothing new is passed to the process. `proc.ld`'s `__heap_start` is the
  same page, so the allocator and the kernel agree.
- *The image ends below 0xD0000000, keeping at least 128 MB of heap.* An
  image that left the heap a few pages would build, start, and then fail
  `heap exhausted` on some input. The limit makes it fail at link time,
  where `l0 build` can say why. The compiler compiling itself peaks at
  40.7 MB (0085), so 128 MB holds the largest program here three times
  over. It also leaves images room to grow to 256 MB, where 4 MB was the
  cap. This was L0S's first open question.
- *`e_entry` is the entry point,* and a kernel uses it, though `proc.ld`
  keeps `.text.boot` first and the entry at 0xC0000000. A kernel then
  depends on the header, not on the layout's choice.
- *A kernel may refuse an image for another CPU,* by `e_machine`. The
  spec does not require it to, since an image that runs is the same with
  or without the check.
- *No raw option.* L0S will accept both formats while it moves and needs
  no raw image afterward, and no other kernel takes L0's. One format per
  target keeps one thing for a kernel to load.

L0S's second question, whether the 4096 alignment before the data
segment moves riscv64's `.sdata` out of the global pointer's reach, does
not arise. Both riscv64 targets build with `-mno-relax`, so nothing
addresses through `__global_pointer$`.

**What it gives up.** A kernel parses the ELF and program headers, where
it copied bytes before. The L0 kernel does this in L0, and the IR harness
in IR. An image is larger by its headers, the padding that aligns its
segments to pages, and its symbols.

---

## Two maps holding the same entries are the same value

**What changed.** The prelude's `(Map K V)` keeps a table that depends only
on its entries (roadmap 0092), so `eq`, `hash`, and `compare`, which see a
data value's fields (sections 6.8, 6.9, 6.11), see only what a map holds.
Section 6.9 now says so of the library's map, and 6.8 says that a data
type is compared by its fields, so one whose fields keep how it was built
is not compared by what it means. The library gains `map_eq`, which
compares two maps by looking each key up, and `map_pairs`, every entry as
a `(MapPair K V)`, sorted by key. `lib/examples.l0` has `same_elements`,
two sets kept as maps compared with `eq`.

**Why.** L0S compared a volume record holding a `(Map int (array
VolEntry))` with one read back from disk and found them unequal, and
reported that two maps with the same entries were not `eq`, hashed apart,
`compare`d 1, and missed each other as keys, with seven tests that each
built the same entries two ways; all seven failed here too. L0S wrote
`vol_same`, comparing the map key by key, to work around it. The table
leaked its history into its fields five ways: unused slots held copies of
the first key and value put, or of the put that grew the table; a removed
entry's key and value stayed in its slot; the table grew and never shrank;
and linear probing kept colliding keys in the order they arrived. Nothing
in `l0 doc Map` warned of it, and the `l0-code` skill says `eq` compares
values by what they hold.

**The decisions.**

- *Make the table canonical, rather than only document it.* Documenting it
  would have left a value that `eq` gets wrong silently in a record, a
  list, or another map, which is the mistake an agent writing L0 would
  make. The user asked for both: the fix, and `map_eq` and `map_pairs`
  beside it. `map_eq` is now always `(eq a b)`; it stays as the comparison
  that needs no argument about the table, and `map_pairs` gives the
  entries in an order every holder of the same entries shares.
- *Slots hold `(MapFree)` or `(MapUsed k v)`,* in one array beside the
  marks, where keys and values were two arrays. An empty slot needed a
  value of the key's and the value's types to fill it, and only an entry
  could give one; now it holds nothing.
- *The capacity is a function of the count*: the least of 8, 16, 32, and
  so on that is at least twice it, as the table grew before, and a remove
  that takes the count below that halves the table. There is no
  hysteresis, since any would let two maps of one count have two sizes.
  So a key put and removed over and over as the count crosses a power of
  two from 4 up rebuilds the table every time; `map_put`'s doc says so.
- *Robin Hood probing, with ties broken by mark and then by `compare` on
  the key,* Blelloch and Golovin's history-independent table (2007): an
  entry farther from its own slot takes a slot from one nearer its own,
  and of two as far the first in that order does. The order is total,
  since `compare` is (6.11), so every run of full slots holds its entries
  in one order whatever order they arrived in. `compare` runs only when
  two keys' hashes are equal. Removal shifts the entries after the removed
  one back a slot each, up to an empty slot or one in its own slot, which
  keeps the order.

**What it costs.** Timed with `tmp/` builds of one program: a million
string keys put went from 221 to 291 ms and got in the same 300 ms, and
a 1,000-key window slid over 200,000 int keys by put and remove from 11 to
22 ms, from the slot each entry now allocates and the probing's distance
arithmetic. The compiler, whose pad table is a map, compiles itself in
0.25 s either way, and emits the same bytes whichever map it was built
with; its own IR grew from 1,468,219 bytes to 1,504,269. Nothing copies
that did not: `tests/io/map_remove_in_place` still requires no array copy.

`tests/unit/map_test.l0` adds L0S's cases, maps grown and shrunk, `map_eq`
of maps that differ, and 60 maps built by random puts and removes, each
compared with the same entries put in key order and in reverse. With the
Robin Hood displacement turned off, five of its tests fail.

---

## The virt board and the process host on riscv64

**What changed.** Section 10.3 has a second virt board, QEMU's riscv64
one, and a riscv64 process host. `l0 build --target virt --arch riscv64`
builds an image OpenSBI boots by the RISC-V Linux image protocol, in
S-mode, with the hart in `a0` and the device tree in `a1`; its parts are
`runtime/arch/riscv64/boot.ll`, `runtime/board/virt-riscv64.ll` and its
layout, and two drivers, `runtime/dev/ns16550.ll` and `runtime/dev/plic.ll`.
It has the 16550 as standard output, semihosting for standard error and
the exit status, the board's devices as regions, user mode on Sv39 with
threads in U-mode, a riscv64 context layout, interrupts by the PLIC, and
the SBI's timer. `--target proc --arch riscv64` is a process making system
calls by `ecall`, and the process's clock is a new system call, 11, which
every kernel answers, the aarch64 harness kernel and the L0 kernel too.
`(machine)` is 2 there, and the library's helpers and `trap_of` read the
riscv64 context; the L0 kernel asks it, too, for the names of a killed
process's fault registers. `tools/test.sh --virt` and `tools/bootstrap.sh --virt`
run everything on both boards. Roadmap 0091, the last of 0087's route.

**Why.** The user asked for the board on riscv64, for the VisionFive 2
later. The parts of 0088 did what they were for: the board is two new
part files, two drivers, and a manifest, and `runtime/bare/board.ll`, the
frame pool, the page walk, the interrupt bookkeeping, and the arguments
from the device tree, serve it unchanged but for one helper, which tells
a riscv64 thread's fault where nothing is mapped from one a page's
permissions make: arm64's syndrome says which, and RISC-V's cause does
not, so the host walks the space and says so in word 34. Word 32 is past
the `ecall`, as it is past the `svc`, so a kernel resumes a thread the
same way on both.

**The decisions.**

- **RAM and the user range.** The riscv64 board's RAM starts at
  0x80000000, so the user range, the 4th gigabyte, is RAM there. It stays
  where section 10.3 has it for both CPUs, and the host leaves that RAM
  unused: with 1 GB the board could not hold a 380 MB heap for `reclaim`
  on the board and 380 MB of frames for `reclaim` as a process of the L0
  kernel, so it runs with 3 GB, its pool in the 5th gigabyte. The pool is
  past what medany code reaches by an address, so the board's part gives
  its bounds as numbers, `l0_board_pool_start` and `l0_board_pool_end`,
  where the aarch64 board's gives its layout's symbols. The VisionFive 2
  and the Pi 4 have RAM in the 4th gigabyte too, and can leave it the same
  way, or use a region table of physical and virtual addresses; not
  decided here.
- **A device's interrupt raised before it is enabled.** On QEMU's riscv64
  board a PLIC source that rises while it is disabled is never taken once
  enabled, which on the aarch64 board it is. The L0 kernel's serial driver
  armed its 16550 before its first wait enabled the interrupt, and hung,
  so the kernel has a call of its own, 262, listen(n), that enables a
  device's interrupt and returns, which the driver makes first. Section
  6.14 does not promise that an interrupt raised before it is enabled is
  taken, so nothing in the language changes.
- **The process's clock.** The time CSR's rate is the board's, which a
  process cannot learn, and an L0 kernel cannot either, so the kernel must
  answer it; a system call was the one way open without a new builtin.
  aarch64's process host reads `cntfrq_el0` and does not need it.
- **The banner.** OpenSBI writes a banner on every boot, on QEMU's
  standard output through semihosting whatever chardev semihosting is
  given (roadmap 0087). So the serial line goes to a descriptor of its
  own, `-chardev file,path=/dev/fd/3`, and QEMU's standard output is
  thrown away; a target's manifest says which it needs.
- **Timer and ASIDs.** The SBI's `set_timer`, not the Sstc extension's
  `stimecmp`, since the VisionFive 2's U74 has no Sstc; and spaces fall
  back to ASID 0 with a flush on every switch on a hart with fewer than 8
  ASID bits, as the U74 is said to have. QEMU has Sstc and 16 bits, so
  neither fallback is exercised here.

## Every L0 function has the fast calling convention

**What changed.** Section 10.2: every L0 function is `fastcc`, and so is
every call of one; only `@l0_f_main`, which the runtime calls, keeps the C
convention. Section 10.3 says why, and that a riscv64 target refuses to
build a program with a tail call of more than 13 words. The compiler's
output changes by the word `fastcc` and nothing else; the seed is
refreshed. Roadmap 0091.

**Why.** On the riscv64 board the compiler crashed compiling itself, with
a null context in `check_call`. Its tail-call components are padded to 9
and 10 words (10.2), and RISC-V's C convention passes 8 in registers, so
the 9th goes on the stack, in the caller's own incoming words. LLVM 23's
RISC-V back end writes that word at the bottom of the caller's frame, the
one the tail call frees, rather than into the incoming words, at every
optimization level, so the callee reads whatever its caller's caller left
there (`tmp/` probes, recorded in roadmap 0091):

```
caller:
	addi	sp, sp, -16
	...
	addi	a0, s0, 40        ; the new 9th word
	sd	a0, 0(sp)         ; written into this frame, over the saved s0
	ld	s0, 0(sp)
	addi	sp, sp, 16
	tail	callee            ; which reads its 9th word at 0(sp), stale
```

aarch64 writes the word where it belongs. LLVM's fast convention passes 13
words in registers on RISC-V, so no tail call of 13 words or fewer puts
one on the stack, and every component of the compiler is narrower. The
choices were:

- **`fastcc` everywhere.** The IR stays the same for every host, and on
  aarch64 and x86-64 the fast convention passes integers as the C one
  does. Chosen. A wider tail call still goes on the stack on
  riscv64, so the target refuses one when the program is built, as
  section 10.3 says a host that cannot honor a tail call does, rather than
  building one that reads stale words
- **passing the words past the 8th in memory,** a block of the
  callee's: it would work at any width, but it changes every target's
  tail calls to work around one back end's bug
- **rewriting the IR for riscv64 when it is linked:** the IR would no
  longer be what the spec says it is

## The library reads a system call wherever the CPU keeps it

**What changed.** `lib/io.l0` has `call_number`, `call_arg`, and
`call_result`, which read a system call's number and its arguments from a
thread's context and set its result, and `trap_of` and `user_context` now
find the call's number and the stack pointer through the same table, by
`(machine)`. Section 6.13 names them. `tests/virt/user/kernel.l0` answers
every call through them and reads no register by its word. aarch64 is the
only CPU so far, so nothing a program sees changes. Roadmap 0090, the use
0089's builtin was for.

**Why.** The library's `trap_of` read `x8` as word 8 and `user_context`
wrote the stack pointer to word 31, and the L0 kernel read a call's
arguments from words 0 to 3 and wrote its result to word 0, about 25
places, all aarch64's. With them behind three helpers and `(machine)`, a
second CPU is a row in the library's table, and the kernel is the same
program on both. Words 32, 35, 36, and 37, the program counter, the trap's
kind, what the CPU said of it, and the address, stay where section 10.3
puts them on every CPU, so no helper reads those.

## A program asks which CPU it runs on

**What changed.** A new builtin, `(machine)`, section 6.16, returns the
number of the CPU the program runs on: 1 for aarch64, and 0 where the host
does not say, as under an operating system. Section 10.3 has the runtime
call, `@l0_machine`, and the host function, `l0_host_machine`, which
`host-libc.ll` answers with 0 and each CPU's part with its own number.
Section 9.2 says a program that must know the CPU asks it. Roadmap 0089,
the first language step of 0087's route to riscv64.

**Why.** A kernel reads a thread's registers out of its context, and the
library reads them for it: `trap_of` in `lib/io.l0` decodes arm64's
exception syndrome and takes a system call's number from `x8`, word 8, and
`user_context` puts the stack pointer in word 31. On riscv64 the number is
in `a7`, word 17, the stack pointer in word 2, and a trap's cause is a
different register with different values. Nothing in L0 said which CPU a
program was on, so neither could be written once for both
(`roadmap/0089/why.l0`), and the IR is the same for every host (9.2), so
the compiler cannot choose either. The choices were:

- **a builtin naming the CPU.** One library and one kernel, branching on it
  where a CPU decides, and the IR still the same for every host. Chosen,
  with the user
- **a library file for each CPU, chosen by the tools.** No language change,
  but the program, and so its IR, would differ by target, which is what
  9.2 promises it does not
- **the host making the context the same on every CPU,** copying a system
  call's number and arguments into words of their own. That keeps the
  kernel's reading the same, but a thread's machine code, and a context's
  registers, are still the CPU's, so a kernel would still need to know

**What it costs.** One builtin, which is a constant for the whole run. A
program that branches on it holds code for every CPU it knows, and runs
only one.

## A host without an operating system is made of parts, and no language change for it

**What changed.** Section 10.3 no longer names one host file for the virt
board and one for a process. A board's host is now `runtime/bare/board.ll`,
which no machine decides; a CPU's part, `runtime/arch/aarch64/boot.ll`; a
board's part, `runtime/board/virt-aarch64.ll`, with its layout beside it;
and drivers, `runtime/dev/gicv2.ll` and `runtime/dev/pl011.ll`, which take
their device's address. Semihosting, which only an emulator answers, is
`runtime/bare/semihost.ll`. A process's host is `runtime/bare/proc.ll` and
its CPU's `runtime/arch/aarch64/proc.ll`. A manifest,
`runtime/targets/NAME.target`, says which parts a target links, how to build
them, and how QEMU boots its images, and the tools read nothing else about
a target. The tools take `--arch` beside `--target virt` and `--target proc`,
aarch64 the only one so far and the default, and `l0 boot` tells an image's
board from its boot header. What any program sees is unchanged. Roadmap
0087 and 0088, at the user's request.

**Why.** The user asked for the virt board on riscv64 as well as aarch64,
and for later boards, the StarFive VisionFive 2 and the Raspberry Pi 4, to
be less work. In one 1,754-line file, aarch64's boot code, its page
descriptors, QEMU's memory map, the GICv2, the PL011, semihosting, the
device tree, the frame pool, and the interrupt bookkeeping were all one
thing, so a second CPU or board would have been a copy of all of it. Split
by who decides each, a riscv64 board writes only its CPU's part, its
board's part, and the drivers it lacks; the Pi 4, an arm64 board with a
GIC-400 and a PL011, needs only a board's part and its layout. The split is
by who decides, not by size: the frame pool and the page tables' walk are
in the neutral part, since arm64's 4 KB granule and RISC-V's Sv39 both
have three levels of 4 KB tables with 9-bit indices, and only the
descriptors' bits are the CPU's. A leaf maps a frame when its address is in
the pool, which no CPU decides, rather than when arm64's attribute index
says normal memory.

**What it costs.** Seven files where there were two, and a manifest per
target. The parts are bitcode linked into the program as before, so LLVM
optimizes them as one module and the image is what it was.

## Freeing spaces and frames, and unmapping a page

**What changed.** Section 6.13 has three new builtins. `(space_unmap s
va)` removes the mapping at one user page, of a frame or of device memory.
`(space_free s)` removes every mapping of a space and gives back its
tables, and `s` may be given again. `(frame_free f)` gives back a frame,
and `f` may be given again, zeroed, at the same address. Freeing a frame
that some space still maps is a new runtime error, `frame still mapped`,
and unmapping a page that is not mapped is another, `user page not mapped`.
Section 10.3 has the calls, three host functions, and codes 9 and 10. It
also says how the board now hands out its pool: a page given back, as a
frame or as a table, serves again as either, and a space's ASID goes with
its number, flushed from the TLB first. Roadmap 0086, at the request of
L0S, with `space_unmap` added at the user's.

**Why.** Section 6.13 said nothing frees either, and the board handed out
frames, tables, and its 255 spaces by bumping. A kernel whose processes
come and go could give none of it back:

```
(def release ((s int) (fs (list int))) int
  (let r (space_free s)
    (free_all fs)))
```

```
roadmap/0086/why.l0:7:10: error: unknown function space_free
```

L0S kept each ended process's space whole, frames still mapped, and zeroed
it for the next process. That cannot be done for a space that mapped a
device or a shared page, which the next process would reach. So every
driver, window manager, and terminal that ended used up a space for good,
and its probe was refused the 255th spawn with only one process alive.
`space_unmap` lets a kernel take back shared memory from a process that is
still running, which L0S's `shm_share` could not revoke.

**Why freeing a mapped frame is an error.** Otherwise a thread could keep
a page whose frame the host has given to someone else: one process would
read another's memory, the one thing a kernel exists to prevent. The host
counts each frame's mappings, which `space_map`, `space_unmap`, and
`space_free` keep up to date, so the check costs a load. It matches `user
page already mapped`, which refuses the other half of the same mistake.

**Why frames outlive the spaces that map them.** A frame may be mapped in
several spaces, shared memory being exactly that, and may be a device's
DMA memory, which the device can still write after its driver ends. Only
the kernel knows which frames are done with, so `space_free` frees the
space and its tables, and leaves each frame to `frame_free`.

**Why `space_unmap` frees no table.** A table it emptied would have to be
found empty by scanning its 512 entries on every unmap, and the next
mapping nearby would make it again. The tables go with the space.

**What the board does.** Every page of the pool has a state, kept by the
host: free, a table, or a frame and how many mappings it has. A freed page
goes on one free list, which frames and tables both take from before the
pool's untouched middle. A space's slot goes back with its number. Before
a space's tables are freed, `ttbr0_el1` goes back to the boot map, since
the host runs on the last thread's tables between traps, and the TLB is
flushed whole, which drops the ASID's entries and any cached walk through
the freed tables. An unmapped page's entry is flushed by its address and
ASID.

**What the tests can see.** `tests/virt/unit/free_test.l0` runs a thread
that loads a word and returns it, so a translation the TLB kept shows as
the old value. With the flush taken out of `space_unmap`, the thread read
the unmapped frame's 7 where the new frame held 9, and the test failed.
With it taken out of `space_free`, every test still passed: QEMU appears
to drop its TLB whenever the ASID in `ttbr0_el1` changes, which the switch
to the boot map does. Hardware that keeps entries by ASID needs the flush.
The board cannot show that, so the flush stays on the strength of the
architecture's rules.

---

## Freed blocks go back to the host, a chunk at a time

**What changed.** Section 10.3: cons cells and data blocks are cut from
chunks of 1 MiB less 64 bytes, aligned to 1 MiB, rather than from an arena
of 64 MB chunks that was never given back. A freed block still goes on the
free list for its size. A sweep finds the chunks, other than the one being
cut, whose every block is on a free list, takes those blocks off, and gives
the chunks back, keeping up to 4 to make chunks from. One runs as a chunk
is made, once the chunks made since the last are a quarter of all there
are, and whenever the host has no memory for an allocation, before the
runtime asks again; that one gives back everything it can, the chunk being
cut and the 4 kept among it. The host interface has one new function,
`l0_host_alloc_aligned(align, n)`, with `posix_memalign`'s contract:
`host-libc.ll` calls it, and `freestanding.ll` gives it over its heap.
Roadmap 0085.

**Why.** A freed block went on the free list for its exact size, and the
arena never gave a chunk back, so freed memory reached neither the host
nor any other size. Where the heap is fixed, that is a program running out
of memory it has freed. A process's heap is 380 MiB, and
`tests/virt/reclaim.l0` holds 100 MiB of blocks of one size, frees it, and
does the same at three other sizes. It stopped with `heap exhausted`
under both kernels, though it never holds more than 100 MiB. It passed on
the board, with 1 GiB, and on macOS, peaking at 421 MB resident. A kernel is
the program the current goal is for, and it frees one process's lists and
then needs memory of another shape for the next. The test now ends with an
array of 300 MiB, which fits in a process's heap only once the lists'
chunks are given back.

**Why nothing is counted as blocks come and go.** Four designs that kept
a count were built and measured on the compiler compiling itself, the
workload that matters most and the one with the leanest allocator to
beat. A freed block went to its exact size's list and allocation popped
it: a few instructions. Pages of 64 KiB, one size each, with a free list
and a count of their own, were 15 to 20% slower in cycles, at 16 KiB as at
64, with headers staggered across cache sets, and with the page a block
was freed into moved to the front. A count beside the old lists, in each
page or in each 1 MiB chunk, was 15% slower with 15% more instructions:
about eight per allocation and free, which on that hot path is the whole
cost. Giving each size its own bump arena, with no count, cost nothing, so
what costs is counting, not keeping sizes apart. A sweep that adds up what
the free lists hold, chunk by chunk, needs no count at all, and leaves
allocation and freeing exactly as they were.

**Why a sweep costs no more than the chunks it follows.** A sweep walks
every free list, which holds no more blocks than the chunks hold. Running
one only after a quarter of the chunks' size has been made since the last
bounds all sweeping by a fixed share of the cutting. Counting what arrays
and bytes take from the host too, so that freed chunks would go back before
a large array, made the compiler 20% slower: it takes far more from the
host that way than it ever holds in chunks, and swept every megabyte.
Arrays still reach freed chunks, when the host refuses them, through the
sweep that runs then.

**Why 1 MiB less 64 bytes.** A chunk is given back only once every block
in it is free, so smaller chunks empty sooner, and every chunk costs one
header line a sweep touches. A block of `freestanding.ll` carries 48
bytes beside it, so a block of a full 1 MiB at a 1 MiB boundary leaves no
room for the next at the next boundary: chunks lay 2 MiB apart, and the
runtime's first small allocation after them, its free worklist, landed in
a gap halfway up the heap and split the freed space in two, which is why
the 300 MiB array first failed. Asked for 64 bytes less, and given a block
`l0_host_alloc` already places on a boundary, chunks lie end to end.

**Why a new host function.** Alignment from `l0_host_alloc` alone means
asking for twice the chunk and wasting half, since `free` cannot give back
part of a block. libc has `posix_memalign`, which takes any size, unlike
`aligned_alloc`, which wants a multiple of the alignment; `freestanding.ll`
takes a block larger by the alignment and frees what lies before and after
the aligned part, which its merging reuses. The host interface is not
pinned by the seed, since only `l0rt.ll` calls it.

**What it costs, measured** on macOS. The compiler compiling itself writes
the same bytes, in the same 0.24 s user, with cycles within half a percent,
3.7% more instructions, which the sweeps account for, and 16 KB more at
its peak of 40.7 MB. `tests/virt/reclaim.l0`'s four phases peak at 125 MB
resident rather than 421 MB, at 16% more cycles, the cost of walking lists
of millions of freed blocks; with its array, at 439 MB rather than 736 MB,
since macOS's allocator keeps the freed chunks rather than using them for
an array of 300 MiB.

---

## A frame's address, so a kernel can give a device memory

**What changed.** Section 6.13 has a new builtin, `(frame_address f)`:
the address at which a device reaches frame `f`, a multiple of 4096, the
same while the frame lasts, or -3 if the host lets no device reach
frames, which no host here does. A frame the program was not given is
`not a frame`, as for `space_map`, so on a host that makes no frames,
every call raises it. 6.12's `barrier` now says it orders loads as well
as stores, `space_read`'s and `space_write`'s copies among them. 10.3 has
the runtime call and one host function, says that on the virt board the
address is the frame's physical one and the board's devices see memory
as its CPU does, and that `l0 boot` gives the board modern virtio-mmio
transports. Roadmap 0084, at the request of L0S, the kernel's own project.

**Why.** Every virtio device on the board, a display, a disk, a network,
input, works in memory it reads and writes itself: its queues, the
commands sent to it, its replies. The driver tells it where by writing an
address into its registers, and nothing in L0 gives the address of
anything:

```
(def queue_address ((d IoDevice) (t int)) int
  (let q (frame_new)
    (device_write32 d (add (mul t 512) 128) (frame_address q))))
```

```
roadmap/0084/why.l0:7:45: error: unknown function frame_address
```

L0S's probe, `probes/virtio-gpu/gpu.l0` in that project, guessed the
address from how `host-virt.ll` hands frames out, `0x98000000 + f*4096`,
and with it drove QEMU's virtio-gpu: set up its control queue in three
frames with `space_write`, wrote the guesses into the queue's registers,
and read back the device's display-info reply, written by DMA, with
`space_read`. So the address was the only thing missing. The guess is a
correctness hole, not a style problem: when it is wrong, the device
silently writes some other page, and the pool holds the host's page
tables too. It goes wrong as soon as frames are freed, the pool moves,
or the allocator changes, and the prelude cannot know any of that either,
since it is the host's. Only the host can say, and so a builtin.

**Why a frame, and not other memory.** A frame is already memory the
program can share without giving up section 8: it is not the program's,
and the program reaches it only by copying. A device writing it is a
thread writing it, as far as any value goes. A region over RAM, or a
range of RAM fixed for DMA, would be a new kind of memory with builtins
of its own for what frames already are, and 6.12 keeps regions off
memory the program or runtime uses for good reason.

**Why "the address at which a device reaches", and why -3.** On the virt
board that is the physical address. On a machine with an IOMMU, or whose
devices see memory at an offset, it is not, and the builtin gives what
the device needs, which is the only use of it. -3 is for a host with
frames that no device can reach; none here is such a host, but a kernel
that runs on one must not take an address for granted, and a code is how
section 6.3's results already say "not on this host".

**Why the barrier's wording.** It said every region access and every
store made before it completes before any made after. A driver polls the
used ring a device wrote with `space_read`, a load after the barrier, so
it depends on loads being ordered too. `dsb sy` on the board and a
sequentially consistent fence under an operating system already order
both, so only the words changed.

**Why modern transports by default.** QEMU makes the board's virtio-mmio
transports legacy unless told otherwise. A legacy queue is one area at
one page number, which past a few entries needs frames next to each
other, which nothing in L0 gives; a modern one is three areas at
addresses of their own, each in one frame. Nothing here drove either
before; the one program that reads a transport, `tests/virt/device`, now
reads version 2 where it read 1. `L0_QEMU_ARGS` adds
devices to the board, since its own include no virtio device: L0S had
written a wrapper script around QEMU, named by `L0_QEMU`, to attach one.

**Left out.** Cache maintenance: frames are mapped write-back, which is
right on QEMU, whose devices see memory as the CPU does, and wrong on
much real hardware, where a driver would need frames mapped without
caching, or to clean and invalidate them. That is the next request for a
display on real hardware, and waits for one. Runs of frames next to each
other are left out too, since nothing modern needs them: virtio-gpu takes
a list of pages for a framebuffer.

**How it is tested.** `tests/virt/frame_dma` makes a real device write a
frame with no device beyond the board's own: the firmware configuration
interface's DMA, given a request in a frame, by the frame's address,
copies its signature, `QEMU`, into the same frame, and `space_read` finds
it there. `tests/io/frame_unknown` is `not a frame` for a frame never
given, on every host.

---

## A process's image is raw, as its kernel loads it, and no language change for it

**No semantic change. L0 is exactly the language it was before this entry.**
`l0 build --target proc` writes a process's image raw, its bytes from
0xC0000000, which is what section 10.3 says a kernel maps; it wrote an
ELF. Section 10.3 now says so. Roadmap 0082, the second of the gaps 0074's
Log named before a kernel's own project.

**Why.** A kernel on the board reads its processes' images from its
standard input, and what it loads is those raw bytes. From an ELF, they
took `llvm-objcopy`, which `tests/virt/user/bundle.sh` and the IR
harness ran and a project using the installed toolchain has no name for,
so it could not make its kernel's input. What the toolchain writes for a
target is now what that target's loader loads: the board's image raw for
the arm64 boot protocol since the last entry, and a process's raw for its
kernel. How a kernel's input lays its images out stays the kernel's, as
its calls are (section 6.15).

**What it gives up.** An ELF's segments say which bytes are code and
which data, which a kernel mapping code read-only and data never
executable would want. No kernel here does yet; one that does is the
reason to write the ELF beside the raw image.

---

## The virt board gives arguments, by the arm64 boot protocol

**What changed.** A program on QEMU's virt board has arguments: its boot
arguments, the device tree's `/chosen/bootargs`, split at runs of spaces.
The board's image now boots by the arm64 boot protocol, Linux's, which
hands the device tree over in `x0`: a raw image with the protocol's
header, where it was an ELF. Section 10.3 says so; section 9.2's absence
of arguments no longer applies to the board. `l0 boot IMAGE ARG...` and
`l0 run --target virt -- ARG...` pass them, by QEMU's `-append`, and
`l0 test --target virt` names its test by one, as it does here. Roadmap
0083.

**Why.** A kernel must be told at boot what to do with the images it is
given: which process is the serial driver, and the driver's device and
interrupt, so that it can start the driver with them through the
arguments call 0077 gave processes for that. `tests/virt/user/kernel.l0`
had all of it in its standard input, in a format of its own, which mixed
the payload with the configuration; a real boot keeps the two apart, the
images as a loaded file and the configuration as a command line. And the
board refused any argument:

```
$ tools/l0 run --target virt roadmap/0083/why.l0 -- driver=1 base=0x09000000 irq=33
l0: the virt board gives a program no arguments
```

**Why the boot protocol.** `roadmap/0083/probe.ll` found that QEMU gives
a bare-metal ELF nothing: `x0` is 0, `-append` goes nowhere, and no
device tree is at the bottom of RAM, though `host-virt.ll`'s memory map
said one was. The same code with the protocol's header, booted as a raw
image, gets the device tree's address in `x0`, with `-append`'s text in
it. U-Boot and the Raspberry Pi's firmware boot an arm64 kernel the same
way, the Pi with `cmdline.txt`, so one host file serves QEMU now and a
board later.

**Why split at spaces.** A command line has no quoting a board's
firmware agrees on, and an argument with a space in it is rare enough
for a kernel's configuration that refusing it is the simpler promise: `l0
boot` refuses one, rather than splitting it in two.

**Why copied out first.** The protocol puts the device tree wherever the
firmware chose, QEMU at 0x48000000, and the host knows nothing of that
range. It copies the arguments into its own memory before the program
starts, while nothing else has touched any, and the image is now bounded
below 0x48000000, its bss zeroed by the boot code rather than trusted to
QEMU's empty RAM, which a board does not promise.

---

## l0 test runs on the virt board, and no language change for it

**No semantic change. L0 is exactly the language it was before this entry.**
`l0 test --target virt` runs tests on the board, booting the program once a
test, and `tools/test.sh --virt` runs `tests/unit` there, and
`tests/virt/unit`, tests of what only the board has. Roadmap 0081, the
first of the gaps 0074's Log named before a kernel's own project.

**Why.** A project made by `l0 init` is not done until `l0 test` passes,
and a kernel's functions that make spaces, run threads, or take
interrupts do nothing on an operating system (section 9.2). `l0 test`
refused the board, since it named the test to run by an argument, and the
board gives none.

**How.** On the board the test's name is the first line of standard
input, which the board has, read by a function of `lib/test.l0`. It was
first written in the generated `main`, where `tests/unit/shadow_test`
broke it: its own `is_empty` shadowed the builtin there, since a
program's definitions shadow every name in it but the library's own
calls (section 7.1). What the board lacks, a test there lacks: files, so
`check_file` fails and `--bless` is refused, and an environment, so
`L0_RC_CHECK`'s leak check is not made. Five of `tests/unit`'s files need
files or an operating system's absence of devices, and say so in a
`.host` file, as `tests/io`'s programs do.

---

## A process calls its kernel's own system calls

**What changed.** Section 6.15 is new, with three builtins: a process
makes its kernel's own calls, numbered from 256, with `supervisor_call`
(three words in, a word back), `supervisor_send` (a word and a range of
bytes), and `supervisor_receive` (a word and room for bytes, which come
back). A call numbered below 256 is the new runtime error `system call
reserved`. 9.2 says every host but a process has no kernel to call, and
10.3 has the runtime calls and one host function. Roadmap 0080, 0074's
item 6.

**Why.** A serial driver that is a process cannot be written: it must
ask its kernel for the bytes other processes sent it, and they must send
them, and `host-proc.ll` makes only the host's ten calls:

```
(def serve ((u int)) int                             ; the driver's loop
  (let b (supervisor_call 257 0 0 0)                 ; the next byte sent
    (let w (uart_put u b) (serve u))))
```

```
roadmap/0080/why.l0:12:10: error: unknown function supervisor_call
```

**Why bytes as well as words.** 0074 sketched one call from words to
words. The user chose bytes too: the goal's measure carries the
compiler's output, 1.3 MB, through a driver that is a process, and three
words a call would take tens of thousands. A range of bytes goes to the
kernel as its address and count, which the kernel copies with
`space_read` or `space_write` (6.13), as it already does for the host's
own read and write; the process names no address, and no L0 value points
into it, so section 8 holds.

**Why the low numbers are refused.** The runtime keeps state about the
calls numbered below 256, its handles' buffers and its arguments. A
program making one itself would go around that, so it is an error, and
spec 10.3's split of the numbers, made in 0077 for this, is enforced
where a program could break it.

**Why no library type.** 0074 expected one over the call. But what call
256 means is the kernel's, and differs between kernels; a type for it
belongs to the kernel's project, beside the kernel that defines it.

**How it is tested.** `tests/virt/user/kernel.l0` defines six calls of
its own: 256 sends bytes, 257 receives them, 258 waits until all that was
sent is written, 259 and 260 wait for a device's interrupt and end it, and
261 sleeps. A client process sends lines through a serial driver process,
which writes them to the PL011 through a region a byte at a time, waiting
for the device's transmit interrupt after each; the driver blocks while
nothing is sent, and the client while its lines are unwritten. A process
asleep alone leaves the kernel nothing to run, so the kernel waits for an
interrupt, the first use of `interrupt_wait` by a kernel. The driver's
interrupt alone would not test that: it arrives while the driver still
runs, before it asks to wait, so the kernel keeps it for the wait.

---

## Interrupts: a timer deadline, and taking, waiting for, and ending one

**What changed.** Section 6.14 is new, with four builtins: `timer_at` sets
the timer's deadline on the clock; `interrupt_enable` lets an interrupt
reach the program; `interrupt_wait` waits for one, takes it, and gives its
number; and `interrupt_done` ends one taken. An interrupt while a thread
runs ends its `user_run`, taken, its number in the context, and the
library's `TrapInterrupt` carries it. Interrupt 0 is the timer's on every
host. Section 8 gains `interrupt not taken`; 9.2 says an operating system
and a process have no interrupts; 10.3 has the runtime calls, four host
functions, the virt board's interrupt numbers, and its regions without the
GIC, which the host now drives itself. Roadmap 0079, 0074's item 4.

**Why.** `tests/virt/user/kernel.l0`, the kernel in L0 0078 made, now runs
several processes. Beside `spin.l0`, which never traps, `preempted.l0`
never ends under it: killed after 30 s, where the IR harness, whose timer
preempts, runs the pair in 0.19 s. The kernel's slice cannot be written:

```
(def slice ((s int) (c (array int))) (array int)
  (let t (timer_at (add (clock_ns) 10000000))
    (user_run s c)))
```

```
roadmap/0079/why.l0:6:10: error: unknown function timer_at
```

**Why the host owns the controller.** 0074 found the stub drove the GIC
with six 32-bit accesses an L0 kernel could make through regions, and the
0075 entry said a kernel's interrupt controller would start that way. The
user reversed that, in 0074's Log, for two reasons. Taking and ending an
interrupt is on every trap's path, and its format is the hardware's, the
test that put the vectors in the host file. And a kernel that drives a
GIC runs only on boards that have one: the Raspberry Pi 3B has none.
Behind builtins, a kernel names an interrupt by a number and the host does
the rest, so the GIC's three ranges leave the regions, and no program can
disable or take an interrupt behind the host.

**Why 0 is the timer's.** A kernel needs the timer to preempt, on every
machine, and with the timer at 0 it names it without knowing the board's
number for it (27 on virt). A device's interrupt keeps the machine's
number, which its driver must be given with its registers anyway.

**Why the whole set, with only the timer's program.** The user chose the
set 0074's Log decided, enabling, waiting, and ending, over the timer
alone, so that a driver, the next item that needs interrupts, starts from
an interface already fixed. `tests/virt/interrupts` takes the PL011's
interrupt as a driver would, so each builtin has a program.

**Why taken until ended.** An interrupt is level-triggered on this board,
the timer's included: it stays pending while its cause holds. Taking one
and ending it apart, as the GIC does, gives the kernel the time between to
remove the cause, a new deadline or a device's register, so the same
interrupt does not come straight back.

**What it costs.** `tests/virt/device.l0` wrote every width to the GIC
distributor's priority registers and read them back, and no other device
on the board keeps what is written at 16, 32, or 64 bits: the PL061's
direction register keeps one byte. Those writes are now checked by the
byte the PL061 keeps, at every width. The user chose this, over keeping
the GIC a region.

**What it does not do.** No interrupt is ever disabled again once enabled,
since nothing yet needs one disabled; a driver stops its device instead.
One processor only, as everywhere here.

---

## User mode: address spaces, frames, and running a thread until it traps

**What changed.** Section 6.13 is new, with seven builtins: `space_new`
and `frame_new` give an address space and a zeroed 4 KB frame; `space_map`
maps a frame at a user page with read, write, and execute permissions;
`space_map_device` maps a device's pages; `space_read` and `space_write`
copy bytes out of and into a space; and `user_run` runs the thread whose
registers an `(array int)` context holds until it traps, and returns the
context updated. Section 8 gains seven runtime errors for misusing them,
9.2 says an operating system and a process have no user mode, and 10.3
has the runtime calls, six host functions, and what the virt board gives:
the user range, the 4th gigabyte; a pool of frames apart from the heap;
and the aarch64 context of 104 words. The library's `Trap` and `trap_of`
decode a context's trap, and `user_context` makes one. Roadmap 0078,
0074's item 5, of the goal "A new goal: a microkernel written in L0".

**Why.** The one kernel that runs processes here,
`tests/virt/proc/harness/kernel.ll`, is hand-written IR, and its loop cannot
be written in L0:

```
(def step ((s int) (c (array int))) int
  (let r (user_run s c)                       ; back at the thread's next trap
    (if (eq (array_get r 35) 1)               ; an interrupt: run it again
        (step s r)
        (array_get r 8))))                    ; else the system call's number
```

```
roadmap/0078/why.l0:5:10: error: unknown function user_run
roadmap/0078/why.l0:11:10: error: unknown function space_new
```

It comes before the timer and interrupts, 0074's item 4, by the user's
choice: one program alone on a board can already poll a device, so nothing
failed without interrupts, and this loop fails at its first line. Once a
kernel in L0 runs two processes, `tests/virt/proc/preempted.l0` fails
without a timer, and that is item 4's Why (0079).

**Why handles, not page tables.** 0074 drew the line: what the hardware's
formats decide, descriptor bits, ASIDs, the TLB, saving registers, and
`eret`, stays in the host file; what a kernel decides, which thread runs,
what it may reach, how a fault is answered, is L0. Its prototype found
that one wrong descriptor bit maps the kernel into a process or makes its
code writable, and that is the bug a handle keeps out of L0: a space and a
frame are numbers, a mapping takes only frames from the host's pool, and a
copy is the only way into or out of a space. A kernel that maps the wrong
frame gives a process the wrong page, never the kernel's own memory, so
section 8's guarantee holds of a kernel as it does of a driver.

**Why 4 KB pages.** The prototype mapped 2 MB blocks, which cannot keep a
process's code from being writable, nor map one device without its
neighbours, and a process's region call maps single device pages. One
size serves both. It costs the compiler, compiling itself as a process
of the kernel below, 8,864 page faults where 2 MB blocks took 20, and that
run takes 7 s, against 6 s under the IR harness's 2 MB blocks and 5 s
on the bare board.

**Why a context is an array.** A thread's registers are 104 words on
aarch64, read and set by the kernel at every trap: the system call's
number and arguments, its result, the address that faulted. An `(array
int)` holds them with no new type, and 0076 made the loop that hands the
same context back to `user_run` each time update it in place, as written.
The layout is the host's to give, in 10.3, since it is the machine's.

**Why copies are bytes.** A kernel answering a process's write must read
the process's buffer, and one answering a read must fill it. As bytes, the
kernel holds a copy, never an address in the process, which 0074 found was
the alternative to a pointer. They reach only frames, so a device page is
never read as memory by accident.

**Why misuse is a runtime error, and exhaustion a code.** A space that
does not exist, a page mapped twice, or a copy from memory never mapped is
a bug in the kernel, as an array index out of range is in any program; a
pool or ASIDs running out is a state a kernel must handle, so it is -5, as
a full table of regions is.

**How it is tested.** `tests/virt/user/kernel.l0` is a kernel in L0, 206
lines with its comments: it reads one process image from its standard input, maps it, and
runs it, answering spec 10.3's ten system calls, mapping the heap and
stack a page at a time as they fault, and reporting a fault it cannot
answer. `tools/test.sh --virt` runs every `tests/virt` program as its
process against the board's expectations, and `fault.ll`, which it must
kill; `tools/bootstrap.sh --virt` has the compiler, as its process,
compile itself to the same bytes. `tests/virt/user_mode` checks each
builtin's results and every kind of trap, a `user_` test each of the
errors, and `tests/io/user_absent` the absence of user mode here.

**What it does not do.** Nothing frees a space or a frame yet, so a kernel
that runs processes one after another runs out; freeing needs the TLB
flushed by ASID and a frame known to be mapped nowhere, which waits for a
kernel that ends processes. No interrupt reaches a thread yet: that is
0079. And a context's layout is aarch64's, since that is the one machine
with user mode.

---

## A host for programs run as processes by a kernel

**No semantic change to a program.** What an L0 program means is what it
was; what is new is a third kind of host. Section 9.2 says a host may be a
kernel that runs the program as a process, unprivileged and in an address
space of its own, and that such a host names no machine. Section 10.3
fixes what a kernel must give one: the process's layout, how a system call
is made, and ten calls, numbered 1 to 10, with numbers below 256 kept for
the host and a kernel's own from 256. `runtime/host-proc.ll` is that host
file, `runtime/proc.ld` its layout, and `l0 build --target proc` builds a
process image. The allocator and the `mem` functions both hosts without
libc need move from `host-virt.ll` into `runtime/freestanding.ll`, which
carries no triple and is linked beside either. Roadmap 0077, the third item
of the goal "A new goal: a microkernel written in L0".

**Why.** Roadmap 0074's prototype ran the compiler as a process at EL0
under a kernel stub, preempted beside a process that never yields and one
the kernel killed, to the seed's bytes, with `runtime/l0rt.ll` and the
program unchanged. It did so through scripts and a host file only
`roadmap/0074/` had:

```
$ tools/l0 build --target proc roadmap/0074/progs/echo.l0 -o tmp/echo-proc.elf
l0: unknown target proc; the targets are host and virt
```

and the spec named two hosts, an operating system and a machine with
none, not a process.

**Why the system calls are fixed by the spec.** The kernel is to be
written in a project of its own, against the installed toolchain, and its
programs are built by that toolchain's `host-proc.ll`. The calls are the
interface between two repositories, so they belong where the rest of the
runtime's interface is, and they are numbered once: a call added later
must take a number no kernel already gave its own, which is why the host
keeps everything below 256.

**Why these ten.** 0074 found that only what leaves a process needs the
kernel: the streams, opening, closing, renaming, removing, and exit. The
allocator works over the process's own heap, and the clock is the virtual
counter, which a kernel lets EL0 read. Two more are here because a driver
needs them and a board should not be written into one: the arguments, so
that a kernel can start a driver with its device's base and interrupt
rather than the driver naming them, and the region call, so that the
kernel maps the device into the driver's space and decides whether it may.
With both, a driver for the PL011 serves every board that has one, and the
kernel image is the same on all of them; 0074's Log has the reasoning
about a second board. `tests/virt/device.l0` and `region_ranges.l0`, run as
processes, are the code that earns the region call; `tests/virt/proc/args.l0`
earns the arguments.

**Why a path goes as bytes and a count.** A kernel reading a NUL-terminated
string from a process must find its end before it knows whether it may
read it, and every byte might be on a page the process does not have.
With a count, the kernel checks one range, as it does for a buffer.

**Why a fixed layout.** `host-proc.ll` must know where its heap and stack
are before it can call anything, and with no loader beneath it the linker
script is where that is said, as `virt.ld` says it for the board. A
kernel that maps those ranges runs every image; one that put them
elsewhere would need a host file of its own, which is what 9.2 rules out.
4 MB for the image holds the compiler, about 800 KB, five times over.

**Why `freestanding.ll`.** `host-proc.ll` needs the allocator and the
`mem` functions `host-virt.ll` already had, unchanged, and two copies of
hand-written IR would drift. Neither names a machine, so the file carries
no triple, like `l0rt.ll`. It also defines `strlen`, which section 10.3
now lists beside `bcmp`: the first process image would not link,

```
ld.lld: error: undefined symbol: strlen
>>> referenced by out.ll
>>>               bare.o:(l0_arg)
```

since LLVM makes `l0rt.ll`'s loop that measures an argument a call to
`strlen`. On the board that loop is dead code, with no arguments to
measure, so nothing had shown it.

**How it is tested.** 0074's kernel stub moves to `tests/virt/proc/` as a
harness, as `tests/backend` holds hand-written IR: a kernel in IR that
answers the ten calls, gives the first process arguments, maps a device
into a process's space by 4 KB pages, and kills a process that faults.
`tools/test.sh --virt` runs every `tests/virt` program as a process under
it, against the board's own expectations, and the process tests in
`tests/virt/proc/`: arguments, a process preempted beside one that never
yields, and one beside a process the kernel kills.
`tools/bootstrap.sh --virt` checks the fixpoint as a process too, which
takes 6 s, as on the bare board. The suite passes 86, from 73, in 120 s,
from 97. The harness stays the virt board's, since it drives the GIC; it is
a harness, not the kernel.

**What it does not do.** A kernel in L0 cannot be written yet: user mode,
address spaces, and traps are 0074's item 5. Nothing reads process images
from standard input yet; the harness has QEMU's loader place them.

---

## An element of an array updates in place through any function

**What changed.** Section 6.5's one in-place form for an element of an
array, `(array_set g y (array_set (array_get g y) x v))`, is now an
instance of a general one: `(array_set g y (f ... (array_get g y) ...))`
for any function or builtin `f`, with `g` one variable that no other
argument of `f` mentions. When `g` has no other holder the element is
taken out for `f`, which is then its only holder, and `f`'s result goes
back in its place. Section 10.3 says the compiler emits the argument as a
new runtime call, `l0_array_take`, which allocates nothing. Roadmap 0076.

**Why.** Roadmap 0074's `progs/kloop.l0` is an L0 kernel's loop with
`user_run` simulated: a table of three 102-word thread contexts, and per
trap one context handed to a function that consumes it and returns it
updated. Written the natural way, it copied the context on every trap:

```
(natural (array_set g t (sim_run (array_get g t) k)) (add k 1) n)
```

```
l0: array copies: 1000000
l0: array words copied: 102000000
```

48 ns a trap, against 12 ns for the same loop written with the context
taken out by hand and an empty array left in its place, which updates in
place. That workaround is right, and an agent writing a kernel would not
find it; the plain form is what anyone writes, and it was the one that
copied. A kernel's thread table, a scheduler's queues, any table of
records each updated by a function, has this shape.

**Why the element can be taken out, and nothing sees it go.** The form
names `g` once more, in the outer `array_set`, and nowhere else among
`f`'s arguments, and `f` cannot see `g`, since L0 has no state outside a
function's parameters. So between taking the element and putting `f`'s
result back, nothing reads `g`. The hole is a 0, the empty list, which
`@l0_dec` already treats as nothing to release. A program that fails in
`f` ends, and never sees it either.

**Why nothing changes when `g` is shared.** Taking an element out of an
array another holder also has would change that holder's array. So then
`l0_array_take` only adds a reference, as `array_get` does, and `f` copies
the element as the plain reading says it must. That is also why the take
allocates nothing in either case: copying `g` early to make it its own
would move a `heap exhausted` ahead of `f`'s own failures, which the plain
reading puts first. `g` is made its own, as before, by the outer
`array_set`, after `f` returns.

**Why the nested form keeps its own runtime call.** `l0_array_set_row`
already does in one call what the general form does in three, for the
case 0025 measured, and the general form gives the same counts and the
same order of errors for it. Keeping it leaves every program that uses it
emitting exactly what it did.

**Why only for counted elements.** An `int` or a `bool` has no holder, so
`array_get` of one shares nothing, and there is nothing to take.

**What it does not cover.** An element bound by a `let` first, or read by
another argument of `f`, is still shared, as 6.5 says. A `let` would make
the binding a holder the language promises to keep, and an argument that
reads `g` is evaluated while the element would be missing.

---

## Regions: a program reads and writes a device's memory

**What changed.** Section 6.12 is new: `region_open` opens a range of a
machine's device memory as a region, `region_read8` to `region_read64` and
`region_write8` to `region_write64` read and write it in one access of
that width, and `barrier` completes every access before it before any
after it. Section 8 gains their three runtime errors and says the
guarantee holds of a program that drives devices; section 9.2 says a host
may have no devices, and an operating system is one; section 10.3 has the
runtime calls, two host functions, and the virt board's devices. Roadmap
0075, the first item of the goal "A new goal: a microkernel written in
L0".

**Why.** No L0 program could touch a device. This is the PL011 driver
0074 could not write, and every driver a microkernel runs, and the
kernel's own interrupt controller, starts the same way:

```
(def put ((b int)) int
  (if (eq (bit_and (load32 (add (uart_base) 24)) 32) 32)
      (put b)
      (store32 (uart_base) b)))
```

```
roadmap/0074/progs/uart.l0:8:20: error: unknown function load32
```

**Why a handle over a range, not loads and stores at an address.** "The
route to memory management and I/O" chose safe facilities over raw memory
because raw memory gives the checker nothing, and 0074 found the same in a
kernel: one wrong bit in an address or a descriptor reaches the runtime's
heap. A region is opened over a range the host has checked is a device, and
every access is checked against it, so a mistake in an offset is a runtime
error naming it, not a store into a value the program holds. What a read
returns is an integer, so nothing from a device becomes a pointer. That is
what lets section 8 keep its guarantee rather than give it up for programs
that drive devices.

**Why the width is in the name.** A device register has one width, and an
access of another may fault or do something else: the checker should
catch a wrong one, and it can only when the width is part of the name.
`region_read 3` would be a runtime error at best. Eight names cost an agent
nothing to read; a width argument would cost it a run to find the mistake.

**Why misaligned is an error of its own.** On the machines L0 runs on, an
unaligned access to device memory faults, and the fault would stop the
program with the host's machine exception rather than a message. Checking
it before the access, after the range, makes it the program's error, said
in words. The three errors are checked in the order a reader would look
for the mistake: which region, then where, then how.

**Why no close.** A driver opens its device once and keeps it, and the
virt board's devices are few: nothing here needs one, and a table of 64 is
more than the board has devices. -5 says when it is full. A kernel that
gives regions to processes will need to take them back, and that is when
closing earns its place.

**Why the barrier is a builtin, and ordering among accesses is promised.**
Volatile accesses to device memory reach one device in order, and that is
what the virt host's map makes them, Device-nGnRnE, so a driver of
registers needs nothing more. A driver of DMA writes a descriptor to
ordinary memory and then rings a doorbell register, and only a barrier
orders those two; without it the device can read a stale descriptor. It is
`dsb sy` on the board and a fence where there are no devices, and is a
builtin because which instruction it is belongs to the host. A kernel per
core will need more, an atomic operation on a region with an ordering, and
that waits for it.

**Why the board gives regions only over a fixed table of its devices.**
QEMU raises an external abort for an access where nothing is mapped, which
would stop the program with a machine exception. The virt board's memory
map is fixed by QEMU, so a table in `host-virt.ll`, which section 10.3
lists, says which ranges are devices without parsing the device tree, and
keeps RAM, and with it the runtime's heap, out of every region. Frames of
RAM for DMA come with address spaces, later.

**What an operating system gives.** No regions: `region_open` is -3, as
opening a file is on a host with none. A program under an operating system
reaches devices through its files, and the runtime does not ask libc for
more, which keeps `host-libc.ll` the same text on macOS and Linux.

---

## A new goal: a microkernel written in L0

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what L0 aims to be: the README's "What
L0 aims to be" gains "A microkernel", and roadmap item 0074 breaks it down.

**The goal.** A microkernel written in L0 runs on QEMU's virt board, beneath
drivers and programs that are L0 processes, each in an address space of its
own. The kernel holds the policy: which process runs, what each may reach,
how they talk. What the machine must be given in its own formats, trap
vectors, saved registers, page tables, the TLB, stays beneath the program
in the host file, behind builtins the checker can type.

**The measure.** The compiler compiles itself to the same bytes as a process
on that kernel, with its standard input and output carried over IPC by a
serial driver that is an L0 process too, and a driver that fails is stopped
without stopping the kernel. The first half is the measure this repository
trusts most, moved one layer up; the second is what a microkernel is for.

**Why it fits.** Much of what a kernel needs, L0 already has:

- no mutable state is needed if the kernel is one loop that runs with
  interrupts masked, as seL4's does: its state is a value passed from one
  tail call to the next, and section 8 makes that loop use no stack
- tables of threads and capabilities are arrays, which section 6.5 updates
  in place when only the loop holds them
- a trap is a data type, and an exhaustive `match` rejects a kernel that
  forgets one
- section 6.10's bits cover descriptors and registers, and bytes cover ELF
  images and the device tree
- section 10.3's host interface is already the seam a process needs: a host
  file whose `l0_host_*` functions are system calls would run every
  existing program, the compiler included, unchanged as a process

**Why it is worth having.** "The route to memory management and I/O" chose
safe facilities over raw memory, on the evidence of ordinary programs, and
deferred the systems primitives rather than rejecting them. A kernel is the
program that tests whether that choice holds where raw memory is the usual
answer. The first thing a driver needs already fails to check: writing a
byte to the board's PL011 serial port, by waiting on its flag register and
storing to its data register, is `unknown function load32`.

**What it opens, and does not settle.**

- Where the line falls between the kernel's L0 and the host file. Raw
  loads and stores would put more of the kernel in L0, and would let a
  kernel bug map its own heap into a process; handles over regions and
  address spaces keep that out, and put more in the host file.
- What section 8's guarantee becomes once a program reads device memory.
  The candidate is that a region read returns an integer, never a pointer,
  and no region covers the runtime's own memory.
- Whether a driver's DMA is contained, which needs the board's IOMMU, since
  a device writes past the MMU.
- How processes are preemptive while the kernel is not: a timer deadline
  before each return to a process, and a kernel pass that runs to its end.
  How long a pass can take matters here, since a release in section 10.3
  frees all a value kept alive before it returns.
- More than one core. Not part of this goal. A kernel per core, sharing no
  L0 value, would need only regions and an atomic operation on one, so the
  facilities this goal adds should not assume one core, and threads within
  a process wait for a program that earns them.
- Where the kernel lives, and how the measure becomes a test here: the
  kernel is written in a project of its own, and each facility is earned in
  this repository by a smaller program in `tests/virt`.

**What it needs that is not here.** Nothing new to install: the board, the
linker container, and QEMU are what the bare-metal goal already uses.

---

## The fixpoint and the compiled suite run on the virt board, and no language change for it

**Nothing in L0 changed.** What is new is a test of the goal's measure.
`tools/bootstrap.sh --virt` builds stage2 as an image for QEMU's virt
board, boots it on the compiler's source, and requires it to write
stage3.ll's bytes there, as it does on the host. `tools/test.sh --virt`
runs that first, and then the compiled suite's programs, `tests/lang`,
`tests/compiler`, and `tests/io`, on the board against the expectations
`--compiled` holds them to, and then `tests/virt`. 0071 met the measure
once, by hand; now a change that loses it fails a test.

**What skips, and why it is stated rather than guessed.** A `tests/io`
program with a `.sh` script skips, since the script examines it through the
host: its files, arguments, signals, or how it was built. So does
`tests/unit`, since `l0 test` names a test by an argument. A program that
needs files or arguments and has no script gets a `<stem>.host` file saying
why. A rule that found such programs by grepping their sources for the
file and argument builtins was tried first and dropped: it took a
parameter named `args` for a call, which skipped twelve compiler stage
tests that run on the board, and every program it rightly found already
has a script. Of the suite's 115 programs, 65 run on the board and 50
skip, 34 for scripts and 16 for `l0 test`; with the fixpoint, 66 pass. The
board has no environment, so `L0_RC_CHECK` is not checked there.

**One container links every image.** The suite starts one container from
`tools/virt/Dockerfile` with the repository mounted at its own path, and
`L0_VIRT_LD` sends each link to it by `docker exec`, rather than a `docker
run` per image, each of which costs 0.19 s to start. `l0 link`, new in the
driver, links IR the compiler wrote, for the host or with `--target virt`
for the board, which is how both scripts build what `tools/l0c` emitted.
`tools/build.sh` now builds the board's runtime into `build/virt` when its
sources change.

**Why roadmap item 0073 is dropped.** It would have let the board run under
Apple's hypervisor instead of emulation, about 24 times faster. The suite
takes 97 s, and emulation is little of it: linking one compiler stage test
for the board takes 2.6 s, nearly all of it clang optimizing the compiler
with the runtime, and booting it 0.14 s. The fixpoint's 5 s on the board is
beside a bootstrap and a link on the host. The hypervisor would save
little, so it waits for a run that emulation makes slow.

---

## A host without an operating system: QEMU's virt board

**No program behaves differently on macOS or Linux.** What is new is a
second host. `runtime/host-virt.ll` is a host file, in section 10.3's
sense, for QEMU's aarch64 `virt` board with no operating system, and
`runtime/virt.ld` lays out its image. `l0 build --target virt` builds an
image, `l0 run --target virt` boots one under QEMU, and `l0 boot` boots
one already built. 10.3 now says that a board's host file names its
machine's triple, since it holds the boot code, and defines `memcpy` and
its siblings where nothing else does.

**The evidence.** Roadmap item 0068 reached the compiler's fixpoint on the
board through prototype scripts, and the driver could not ask for it:

```
$ tools/l0 build --target virt tmp/0068/hello.l0 -o tmp/0068/hello-virt.elf
l0: unknown option --target
```

Now the compiler, built from `lib/prelude.l0` and `compiler/*.l0` by `l0
build --target virt --no-prelude`, and booted with `l0 boot` on its own
source, writes the same 1,275,883 bytes the seed writes on macOS, in 4.96
s under QEMU's emulation. Its heap peaks at 64.3 MB, the runtime's first
64 MB arena chunk and 256 KB of buffers, against 36 MB the same run
touches on macOS.

**What the board gives**, as section 9.2 allows: standard input is the
bytes QEMU's loader puts in memory, since a serial line has no end of
input; standard output is the serial port; standard error and the exit
status reach the host by semihosting, so the three stay apart on a board
with one serial line. There are no files, no arguments, and no
environment, and the generic timer is the clock. An exception the runtime
does not expect, which would be a bug in it, is reported with the
registers that locate it and stops with status 99.

**The allocator splits and merges.** 0068's prototype served every request
from power-of-two classes and never merged, so a block of 64 MB plus one
word took 128 MB, and the space freed blocks held could only be reused at
their own size. `host-virt.ll` keeps each block's size at both ends, so
freeing merges a block with a free neighbour on either side, and keeps
free blocks in 64 bins by the top bit of their size: allocation takes the
first block that fits from the request's bin up, and splits off what is
left when that makes a block of its own. `l0_host_resize` grows into a
free neighbour above before it copies. A block's contents are 16-byte
aligned, as `malloc`'s are.

**One module, built with `clang` alone.** The driver compiles the program
with the board's runtime and host file linked into it as bitcode, by
clang's `-mlink-bitcode-file`, so all three are optimized together, as
link-time optimization does on macOS and Linux, without `llvm-link` or
`opt`. What is left for the linker is placing sections, so ld.lld does it:
`L0_VIRT_LD` if it names one that runs, and otherwise the ld.lld of a
container built from `tools/virt/Dockerfile`, whose older LLVM never reads
the host's bitcode. On the machine this was written on, a security policy
stops the host's own ld.lld from running at all, which is why the
container exists.

**What `--target virt` refuses.** `l0 run --target virt` takes no
arguments after `--`, since the board gives none, and reads all of its
standard input before booting, since the board's input is loaded whole.
`l0 test --target virt` is refused: `l0 test` names the test to run by an
argument.

`tests/virt` holds six programs run on the board by `tools/test.sh
--virt`: section 9.2's cases, a whole-input and a streaming `main`, a
runtime error, stack exhaustion, and the clock. `tools/install.sh`
installs the board's runtime when `clang` can target aarch64, and skips it
otherwise.

---

## The runtime reaches its host through an interface of its own

**No program behaves differently.** Every output, error, and exit status
is what it was. What changed is how the runtime is made: section 10.3 now
names a host interface of 14 `l0_host_` functions, `runtime/l0rt.ll` calls
the host only through it, and a host file implements it. On macOS and
Linux that is the new `runtime/host-libc.ll`, the only file that calls
libc, and it defines the entry point, which calls `l0rt.ll`'s
`@l0_rt_run`. The functions compiled code calls are untouched, so the seed
is too.

**The evidence.** Roadmap item 0068 ran the compiler on QEMU's virt board
by supplying, in `roadmap/0068/metal.ll`, the 30 libc functions `l0rt.ll`
declared. That worked only by steering `l0rt.ll` into fallbacks written
for other reasons:

```llvm
define i32 @pthread_create(ptr %t, ptr %a, ptr %f, ptr %arg) {
entry:
  ret i32 11      ; fails, so l0rt.ll's main runs the program on its own stack
}

define ptr @dlsym(ptr %h, ptr %name) {
entry:
  ret ptr null    ; finds nothing, so errno reads as -1
}
```

and `dup` returning 3 so that the standard descriptors looked open. Any
change to those paths, made for macOS or Linux, would have broken the
board, and nothing run on macOS or Linux would have seen it.

**Why the host gives codes, not errno.** Every interface result that can
fail is a section 6.3 code. errno's numbers, how to reach it (`dlsym` of
`__error` or `__errno_location`), and the probes that tell causes apart
(`access`, `opendir`) are all facts about POSIX hosts, and moved with the
code that uses them into `host-libc.ll`, unchanged. A host without an
operating system then answers in the terms section 9.2 already uses: an
open of a file it does not have is -3 because the host says so, not
because `access` happened to fail.

**What stays in `l0rt.ll`.** The handle table and its buffering, the
conversion of a path list to a NUL-terminated string, the state of a
handle after a failed write, and the stack check: everything section 6.3
says about handles, which is the same on every host. It calls `memcmp`,
which C requires of every environment, an operating system or none, and
LLVM's memory intrinsics, which lower to `memcpy`, `memmove`, and `memset`
that every host must supply anyway.

**Why the large stack is the host's.** Making a thread is a host facility
a board may not have. `l0rt.ll` is given the size of the stack below the
frame it starts in and sets its limit from that, so `host-libc.ll` can run
it on a 512 MB thread, or on the process's own stack when the thread
cannot be made, and a board on its boot stack, without `l0rt.ll` knowing
which.

**Two objects rather than one.** `tools/build.sh` and `tools/install.sh`
assemble the files into `l0rt.o` and `l0host.o`, and every link takes
both. Merging them into one object would need `llvm-link`, which is not
part of what installing needs today, `clang` alone. Keeping them apart is
also what roadmap item 0071 needs: a board's build links another host
object in place of `l0host.o`. `L0_HOST` names it, as `L0_RUNTIME` names
the runtime.

**The host interface is not pinned by the seed.** The seed declares the
`l0_` functions compiled code calls, so those stay append-only. The
`l0_host_` functions are called only by `l0rt.ll` and defined only by a
host file, both linked fresh into every program, so they can change
whenever both do.

`tests/io/host_boundary` checks the boundary: `l0rt.ll` declares nothing
but the host interface, LLVM intrinsics, `memcmp`, and `@l0_f_main`, and
`host-libc.ll` defines every `l0_host_` function it declares. Run on
`l0rt.ll` as it was, it lists 29 libc functions.

**What this costs the prototype.** `roadmap/0068/metal.ll` supplied libc
to the old `l0rt.ll`, and does not link with the new one. It still builds
against `l0rt.ll` as of the commit that added it, and item 0071 rewrites
it as a host file.

---

## What a host without an operating system gives

**No program behaves differently on macOS or Linux.** The new section 9.2
says what a host is, what every host gives a program, and what a host may
lack and what a program sees then. 6.3, 6.4, and 10.3 point to it, and 10.3
no longer says the runtime only ever reaches the host through libc.

**The evidence.** Roadmap item 0068 ran the compiler, and this program, on
QEMU's virt board with no operating system:

```
(def main ((input (list int))) (list int)
  (let t0 (clock_ns)
    (let s (spin 10000000)
      (let t1 (clock_ns)
        (append (line (digits (sub t1 t0)))
          (append (line (digits (arg_count)))
            (line (digits (open_read (cons 120 (nil int)))))))))))
```

It printed 82380992, 0, and -3, each plausible and none specified. -3 came
from the prototype's `access` failing, and `open_write` would have given
whatever the runtime makes of a failed `creat` with no errno. 10.3 said the
runtime "reaches the operating system only by calling libc", and
`L0_STACK_MB` and the other settings came from an environment the board
does not have. The spec was silent exactly where a host lacks something.

**A host without files is an empty file system, not a new failure.** Opening
for reading, renaming, and removing give -3, and opening for writing or
appending gives -9. Three things decided it:

- it is true: nothing is there, and there is no directory to create a file
  in
- a new code would add a case to `OpenFault`, `CreateFault`,
  `RenameFault`, and `RemoveFault`, and since `match` has no wildcard,
  every program that handles those types would stop compiling, on every
  host, for a case that only a board can give
- the program that already handles -3 does the right thing on a board. A
  program that falls back to its defaults when a settings file is missing
  falls back there too, and one that reports a missing directory says
  something true. -5, "any other failure", would have made the common case
  fatal

What no program can do is tell a board apart from an empty directory.
Nothing in this repository needs to, and a code for it can be added when a
program does.

**A missing channel is a stream open on nothing.** A board with one serial
line may have no separate channel for standard error. 6.3 already says what
a stream the host left closed is: open on nothing, reads -5, writes lost and
reported as a write failure. A missing channel is given the same, so no new
state exists, and a program writing to standard error on such a host exits
70, as one started with standard error closed does. The streams themselves,
and an exit status, are required of every host: section 9's two forms of
`main` and section 8's runtime errors cannot be had without them, and how a
host provides them is its own affair, as 0068's prototype provides standard
error and the status by semihosting.

**No arguments, no clock, no environment.** No arguments is `(arg_count)`
0, which 6.4 already allowed. No clock is -5, as 6.7 already said. No
environment makes `L0_STACK_MB`, `L0_ARRAY_STATS`, and `L0_RC_CHECK` as if
unset, and a host that cannot make the large stack's thread runs `main` on
its own stack, which the runtime has always done when `pthread_create`
fails.

**What is left for 0070.** 10.3 says what the runtime does on a machine
without libc, but does not yet name the interface the runtime will call in
place of libc, because nothing implements it yet, and the spec says what
L0 is, not what it will be. Roadmap item 0070 names it when `l0rt.ll` calls
it.

---

## A new goal: running on bare metal

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what L0 aims to be: a goal is added to
the README's "What L0 aims to be", and roadmap item 0068 breaks it down.

**The goal.** An L0 program runs with no operating system beneath it, booted
on a machine with its runtime the only code below it. Where there is an
operating system, libc stays the interface to it, for the reason "A new
goal, and the agent that uses L0 is the one that changes it" below gives.
On bare metal the runtime takes libc's place: memory from a region it owns,
standard input and output over a serial line, the clock from a hardware
timer. It does so behind the same runtime interface, so that a program, and
the IR the compiler emits for it, does not change with where it runs. The
measure is the one this repository trusts most: the compiler compiling
itself on a machine with no operating system, to the same bytes it produces
under one.

**Why it fits.** The pieces it needs are already narrow. Section 10.2 keeps a
target triple out of the emitted IR, so a compiled program does not know its
host. Section 10.3 confines the host to one file of IR and 50 functions,
and a program reaches nothing else. What crosses that boundary
today is 30 libc functions, `malloc`, `read`, `open`, `pthread_create`,
`clock_gettime`, `dlsym`, and the rest, and replacing them is the work.

**Why it is worth having.** It tests a claim the spec makes without having
checked it: that L0's facilities are defined by the spec, not by POSIX.
Section 6.3's failure codes, the 512 MB stack thread, `L0_STACK_MB`, standard
error, and files all assume a host that has them. Where the spec turns out to
lean on one silently, that silence is a bug in the spec, and a host with
nothing beneath it is the way to find every one.

**What it opens, and does not settle.**

- What a program sees where there is no file system, no arguments, and no
  environment. Section 6.3 says what a failed open returns, but not what a
  host without files is.
- Whether there is one runtime or two. Section 10.3 says the runtime
  "reaches the operating system only by calling libc", which a bare-metal
  runtime cannot do, so 10.3 will change.
- Whether a program can do more there than under an operating system, such
  as driving a device or handling an interrupt. That needs the systems
  primitives "The route to memory management and I/O" deferred: loads and
  stores at an address, and static storage. This goal reopens them, but does
  not earn them; a program that needs one does.

**What it needs that is not here.** A linker for ELF images (`ld.lld`) and an
emulator to boot them (QEMU), neither of which is installed on the machine
this entry was written on. Installing them is the user's call.

---

## Renaming a directory onto a file is not a missing directory

**`rename` of a directory onto a file returns -5, not -9** (section 6.3,
roadmap item 0067). The host fails it with ENOTDIR, which the runtime reads
as a missing name, since a file standing where a directory should be on the
way to a name does make that name missing. `from` was there, so the runtime
took the missing name to be `to`'s directory and returned -9, "no such
directory", though that directory exists. It broke 6.3, which gives -9 only
when the host says that is the reason. A program acting on
`RenameNoDirectory`, by reporting or making the directory, would have been
misled. The runtime now gives -9 only when `to` cannot be found either,
and -5 when it can. The spec now says so outright.

**Why -5, and not a new code.** 6.3's -8 is for a `to` that is a directory,
and nothing in the repository renames directories or needs to tell this
case apart. A code for it can be added when a program needs one.

`tests/io/open_faults` renames a directory onto a file and checks that
both names stay as they were. It also checks that a file where `to`'s
directory should be still gives `RenameNoDirectory`.

---

## Reading at most n bytes

**`(read_some h n)` reads the next piece of a handle** (section 6.6,
roadmap items 0060 and 0066): at least one byte and at most `n`, waiting
only while none has arrived, as fresh `bytes`; empty at the end, on a
failure, or if `h` is not open for reading, after which `read_from` says
which, as after `read_bytes`. An `n` below 1 is the new runtime error `byte
count out of range`, since empty bytes would read as the end.
`lib/io.l0`'s `file_read_some` gives `IoBytes`, empty at the end, or
`IoReadFailed`.

**Why.** 0055's failure worker could read a byte at a time or all at once.
Its tee took 1.02 s of user time on 100 MB to four outputs, against the
system's 0.16 s, and its unpacker held a whole archive, 28 times `tar`'s
memory. 0060 measured the whole-input copy at 0.07 s in 103 MB and the
byte-at-a-time copy at 0.14 s in 1.6 MB; a bounded read gives the speed of
one in the memory of the other.

**`write_bytes` copies blocks.** Moving tee onto `file_read_some` only
halved it, to 0.55 s: `@l0_write_bytes` called `@l0_write_to` once per byte,
and whether LTO inlined that call differed from program to program. It now
copies a range into a descriptor's buffer a block at a time, delivering the
buffer each time it fills, which leaves the same bytes in the same order as
before, so section 6.6's "exactly as that many calls of `write_to` would"
still holds. Tee, from `roadmap/0066/tee/`, now copies 100 MB to standard
output and three files in 0.08 s of real time and no measurable user time,
in 2 MB, faster than the system's tee.

**The choices.**

- *Fresh bytes, not a read into a buffer.* That would save one allocation
  per piece, about 1,600 per 100 MB, and needs bytes that update in place,
  which 0060 found nothing here needs: 0058's bitset sieve already runs to
  10^8 in 0.57 s and 14 MB. Bytes stay immutable.
- *No promise to fill the piece.* A terminal or a pipe gives what has
  arrived, and a program that waited for `n` could not answer a prompt; so
  a reader loops until the bytes are empty, and the library says so.
- *At most the buffer's size.* A piece from a file or a pipe is at most
  65,536 bytes whatever `n` is, since the handle reads into its buffer; a
  handle over a list, which has no buffer, gives up to `n` elements. Asking
  for more is not an error, only an upper bound.

`tests/unit/read_some_test.l0` covers pieces of every size from a handle
over a list, the end and after it, a handle not open for reading, and `n`
below 1; `tests/io/read_some` a 1.3 MB file copied in pieces of 1,000 and of
a hundred million, the same through a pipe, and a directory as standard
input, under `L0_RC_CHECK`; `check_errors` the arity and type. The
unpacker is not moved onto it here: streaming its archive in two passes is
a rewrite of its parser, and tee already shows a stream in constant memory.

---

## The library sorts, and takes the min and max, of any type, and no language change for it

**`lib/prelude.l0` has `sort`, `min`, and `max`** (roadmap item 0065), over
the `compare` of the entry below. `sort` is a bottom-up merge sort of a
list: each element a run of one, then pass after pass merging neighbouring
runs, every loop a tail call, so it takes time proportional to n log n and
no stack. A million ints sort in 0.25 s of user time on a 1 MB stack, with
nothing left live under `L0_RC_CHECK`. `min` and `max` give the first
argument on a tie.

**Why.** 0059 found every sort in this repository written for one element
type, wordfreq's and its heap twice, a line sort, Kruskal's merge sort, and
0055's heap and set, and about fifteen int `min` and `max` one-liners in
thirteen files. They are now written once. A sort that is not by the
structural order sorts keys built for its order: `lib/examples.l0`'s
`by_frequency` lists a map's words most frequent first by sorting `(Rank
(neg count) word)`. `map_keys`'s doc now says to `sort` the keys when order
matters, which before 0064 a generic caller could not do.

**Not stable, and not said to be.** Merging takes the left run's element on
a tie, which would keep equal elements in order, but `compare` is 0 only
for values `eq` calls the same, so no program can tell; the doc promises
only the order. A stability promise waits for a comparison that can call
two different values equal, which only function values would bring.

The library's own code takes no int `max` that reads better as the generic
one: `examples.l0`'s `max2` is an example of `if`, and the compiler's two
are folds over fields and edges. `tests/unit/sort_test.l0` covers the edges,
ints at their limits, strings, a record key, `min` and `max`, and 200,000
pseudo-random ints checked for order and for the same elements.

No rule in `spec/L0.md` changed.

---

## `compare` orders two values of any type

**`(compare a b)` is -1, 0, or 1** (section 6.11, roadmap items 0059 and
0064), for `a` of any type and `b` of the same, by an order fixed in the
spec: ints by value, `false` before `true`, lists, arrays, and bytes element
by element with a shorter prefix first, and data values by the constructor's
position in its declaration, then field by field. It is 0 exactly when `eq`
is true. On `int` and `bool` it is two `icmp`s; on anything else a call of
`@l0_compare`, a walk of both values together in order, with a worklist of
its own and no stack.

**Why.** 0055's structures worker could not write a heap or a balanced tree
once for every element type: `(lt a b)` at a type parameter is "an argument
of lt must be int, but this is T". Its named workaround boxed every element
into a closed sum `Key = KInt int | KStr bytes`, 5.2 times slower on the
heap and closed to records, and its `key_cmp` turned out to be exactly the
structural order on `Key`. 0059 inventoried every ordering in this
repository's code: 11 of 21 are structural, and 8 more are once the program
builds a key, such as count highest first and then word, `(Rank (neg count)
word)`.

**Why not function values instead.** They were the other answer, and 0059
weighed them: a function type, names in value position, calls through a
local, a wrapper per function used as a value, owned arguments at the
wrapper, and an exception to section 8, since an indirect call cannot share
every caller's padded prototype; a generic function passed as a value has
no argument to take its types from. And the two orderings here that no key
expresses, 0028's sort of lines by index into one shared buffer, read data
outside their arguments, so function values without closures would not
serve them either. They wait for a program that needs them, and `compare`
changes none of the properties the bootstrap skill lists: it is checked by
`eq`'s rule, with no inference or unification.

**The choices.**

- *An `int`, not a data type of three cases.* `(lt (compare a b) 0)` reads
  as the test it is, and an `int` result costs a `match` nowhere.
- *Arrays as lists are.* An earlier sketch ordered arrays by length first;
  one rule for every sequence is the one to remember, and nothing here
  orders arrays.
- *Not numeric.* The order is of contents: 0055's bignums, kept least
  significant limb first, would compare wrongly, so 6.11 says to give such a
  type a key.

`tests/unit/compare_test.l0` covers every kind and its edges, constructors
of different widths, a key, agreement with `eq`, and both copies of a
generic function; `tests/io/compare_deep` a million-element list and
100,000-deep nesting on a 1 MB stack under `L0_RC_CHECK`;
`tests/io/compare_read_only` that list parameters used only by `compare` are
read-only and that `compare` on ints is instructions; and
`tests/compiler/check_errors` the mismatch and the arity. The compiler and
the prelude use none of it yet; the library's sort over it is 0065.

---

## A declaration that does not parse is reported once, and no language change for it

**The checker no longer reports a dropped declaration's uses** (roadmap
item 0063). A def that fails to parse is dropped and the rest are checked,
as before, but its name is kept, and "unknown function" or "unknown
variable" for that name is not reported: 0055's numbers worker saw a table
it could not declare reported a second and third time as unknown, which
reads as a different mistake. A use of a name that was never declared is
still reported.

**Recovery no longer starts inside a parameter.** After an error the parser
skips to the next `(def` or `(data`, and a parameter named `data`, as in
`((data int))`, was one, so it was parsed as a data declaration and reported
as needing an uppercase name. A declaration is now a `(def` or `(data`
followed by a `(`, or by a name and then a `(`, which a declaration with a
badly formed name still is, so its own error is kept.

`tests/check/parse_dropped_def` and `tests/check/param_named_data` each
expect the one error; the compiler before this gave three for each.

**The rest of 0063 is library and documentation.** `hex_digits` prints a
number in hexadecimal, as the library could read one but not write it;
`map_keys`'s doc no longer tells a generic caller to sort keys it has no way
to order; the shipped guide says `l0 check` accepts a file with no `main`
and where `l0 run` builds; and the shipped skill gives the measured cost of
the file wrappers in a per-byte loop over several files, 2.1 to 2.8 times
the raw handles, and says that only a flush can tell which write failed.

No rule in `spec/L0.md` changed.

---

## Renaming, removing, flushing, and closing say which failure it was

**Five codes join section 6.3's table** (roadmap item 0062): -6 no space
left, -7 the reader of a pipe has gone, -8 it is a directory, -9 no such
directory, the one a file would be in, and -10 on another file system. Each
is given only by the operations the table names, and only when the host
says that was the reason; any other is still -5. With them, opening a
directory to read, to write, or to append, or removing one, is -8 where it
was -5, a directory that may not be written denies creating and renaming in
it (-4) where that was -5, and
`flush` and `close` return the code of the first byte lost rather than
always -5.

**The library types them, as 0050 did for opening.** `OpenFault` gains
`OpenIsDirectory`, and `CreateFault` `CreateNoDirectory` and
`CreateIsDirectory`. `rename_file`, `remove_file`, `file_flush`, and
`file_close` return `(IoDone E)`, `(Done)` or `(NotDone fault why)`, where
`E` is `RenameFault`, `RemoveFault`, or `WriteFault`, each with only the
cases its operation can give, and `is_done` is the test when only success
matters. `io_error` has words for every new code.

**Why.** 0055's failure worker had six causes reaching it as one message,
"input or output failed": a read-only directory, a missing one, a directory
as a target, a full disk, and two failed renames. Its archiver probed the
parent directory with `open_in` to say when a directory was missing (25
lines, named as a workaround), and read `OpenFailed` as "a directory",
which it also was for every other failure. Its tee could not tell a full
disk from a reader that had gone. 0049 had left these codes "until a program
needs more"; these programs needed more. Copies of the three, moved onto the
typed results (`roadmap/0062/`), drop both workarounds, say what to do for a
full disk, a closed pipe, and an archive named like a directory, and pass
their own tests and 0055's interruption harness; the tee, piped into `head
-c 10` and writing 100 MB to a file, reports "the reader has gone" for
standard output and copies the file whole.

**The choices.**

- *Codes in the spec, not only in the library.* A cause the runtime cannot
  report cannot be typed, and the runtime is reached only through 10.3's
  codes, so the cause has to be one of them. Adding codes changes no
  signature in 10.3 and needs no new seed. A program that compared with -5
  for one of these causes now sees the new code; none in this repository
  did.
- *Only errno numbered alike.* ENOSPC 28, EPIPE 32, EISDIR 21, EXDEV 18,
  EROFS 30, and 0057's four are the same on macOS and Linux, which keeps the
  runtime one text. A full directory as `rename`'s target, whose ENOTEMPTY
  differs, is told by `opendir`; EDQUOT differs and has no second way, so
  exceeding a quota is -5. ELOOP and ENAMETOOLONG stay -5, as 0057 decided.
- *One result type for four operations.* `(IoDone E)` beside `(IoOpened
  E)`, rather than a result type per operation, since none of the four has
  anything to return but whether it worked. Its constructors are `Done` and
  `NotDone`, short since every caller writes them, and a program's own
  `Done` shadows the library's (0037).
- *Not forced.* `match` forces a program to handle `IoFailed` only because
  the file is inside `IoOpened`; nothing is inside `Done`, so `(let c
  (file_close f) 0)` with `c` unused still compiles, as `limits/02b` found
  of the `int`. Forcing a result to be used would be a rule of its own for
  L0, about every value or about some types, and is not earned by one
  program; the shipped skill says to look at every close of a file written.
- *The first loss is reported.* A handle remembers the code of the first
  byte lost, and every later flush and the close return it, as 6.3 already
  said of the failure itself.

Every caller in `lib/` and `tests/` moved onto the new results, found by
the checker. `tests/io/open_faults` covers each new open and rename case,
`tests/io/remove` reports cases by name, `tests/io/broken_pipe` requires
`WriteBrokenPipe`, and `tests/unit/io_test` the words and cases, closing
twice, and renaming onto a directory. Not covered by a test: -6, which
needs a full disk, and -10, which needs a second file system inside the
workspace.

---

## Deleting a file

**`(remove path)` deletes a file** (section 6.3, roadmap item 0061), and
`lib/io.l0`'s `remove_file` wraps it as `rename_file` wraps `rename`. It
returns 0, or -3 if nothing is there, -4 if the file may not be deleted, or
-5 otherwise, with the file still there. A directory is never deleted, a
link is deleted rather than what it leads to, and deleting is one step. A
handle already open on the file keeps working until it is closed, which is
what POSIX does and what a program holding a file it has decided to
discard needs.

**Why.** 0055's failure worker could not write `(remove_file
"out.partial")`: `unknown function remove_file`. So a failed pack left
`OUT.partial` behind and said so, an unpacker left a file it could not
finish, and the log rotator kept its journal forever, saying "idle", and
could only name the logs older than it keeps. With `remove_file`, copies of
both, changed for 0061 and not kept, cleaned up: the rotator drops logs past N and then deletes
its journal, last, so a run stopped at any point still resumes rather than
rotating again, which 0055's interruption harness confirms over 536
interrupted runs and 200 kills, now also requiring that a finished rotation
leaves no journal; and a pack whose final rename fails leaves nothing. The
example `replace_file` in `lib/examples.l0` deletes its half-written file
the same way when the write or the rename fails.

**The choices.**

- *A directory is -5, not deleted.* Deleting an empty directory is a
  separate operation with its own failures, and no program here needed it;
  directories wait with listing and creating them (0055).
- *The name.* `remove` is C's name for exactly this, and `remove_file`
  reads beside `rename_file` and was the name 0055's worker guessed.
- *Telling a directory apart.* `unlink` refuses a directory with EPERM on
  macOS and EISDIR on Linux, and EPERM otherwise means denied, so on a
  failure the runtime asks `opendir` first, and only then reads errno, as
  0057 does: ENOENT or ENOTDIR is -3, EACCES or EPERM is -4. Asking before
  `unlink` instead would refuse a link to a directory, which is a link and
  should go.

`tests/io/remove` covers each result and what it leaves, and a handle that
keeps reading a deleted file; two checker cases are in
`tests/compiler/check_errors`.

---

## Bitwise operations

**Six builtins work on the 64 bits of an `int`** (section 6.10, roadmap
item 0058): `bit_and`, `bit_or`, and `bit_xor`; `bit_shl`, and `bit_shr`,
which brings in zeros; and `bit_count`, how many bits are 1. A shift by 64
or more moves every bit out and gives 0, and a shift by a negative amount
is the new runtime error `negative shift`. `bit_and`, `bit_or`, and
`bit_xor` are the LLVM instructions; the shifts and `bit_count` are runtime
calls, `@l0_bit_shl`, `@l0_bit_shr`, and `@l0_bit_count`, added to 10.3.

**Why.** 0055's numbers worker could not write one CRC-32 step,
`(bit_xor (array_get table (bit_and (bit_xor crc b) 255)) (shr crc 8))`.
Its workaround, 137 lines of 64K tables with `div` and `mod`, made one xor
13.1 ns against 1.6 ns for the loop around it, and the CRC-32 and SHA-256
of 100 MB 9.9 s of user time. 0028's grids found masks by `div` and `mod`
17 times slower than flag arrays, and 0055's sieve held 63 bits a word,
since the sign bit could not be reached by arithmetic, and counted them
through a 64K table. Section 6.9 defined `hash` with xor and a logical
shift that no L0 program could write.

**What it bought.** The same program written with them, now
`tests/unit/sums.l0`, takes 2.33 s on the 100 MB, with the same sums: 4.2
times faster, in 268 lines where there were 400, and the CRC register is an
`int` instead of four bytes. The rest of the gap to `cksum` and `shasum`
(0.35 s together) is not in the bits: it reads a byte at a time and builds
a state of eight fields per round.

**The choices.**

- *Names.* The `bit_` prefix keeps them together, as `array_` and `bytes_`
  do, and leaves `and`, `or`, and `not` to `bool`. 0031's rule means a
  program that already defines one of these names keeps its own.
- *Shifts past the word.* LLVM gives a shift by 64 or more no value; L0
  gives the one the bits imply, 0, so `(sub (bit_shl 1 n) 1)` is the mask of
  `n` bits for every `n` from 0 to 64 and needs no special case at 64. A
  negative amount has no such reading, and is more likely a mistake than a
  request to shift the other way, so it fails where it happens.
- *Left out.* A shift right that copies the sign, since no program here
  needed it and `div` by a power of two already divides a negative integer;
  a bitwise not, which is `(bit_xor x -1)`; a rotation, since the one SHA-256
  needs is of 32 bits within a 64-bit `int`, two shifts and a `bit_or` under a
  mask; and hexadecimal literals, which 0055 also asked for, as a separate
  change to section 2.1 waiting for more code than constants read from a
  string once.

Stage 0 is frozen and knows none of them, so the tests are in `tests/io`
(`bits`, every example 6.10 gives, the edges of the shifts, and a CRC-32
check value; `bits_negative_shift`) and `tests/unit/sums_test.l0` (18
published CRC-32 and SHA-256 vectors), with five checker cases in
`tests/compiler/check_errors`. The compiler's own source uses none of them;
the seed is refreshed so that `tools/l0` compiles programs that do.

---

## A broken pipe is a write failure, a closed standard handle is open on nothing, and -3 means nothing is there

Three places where the runtime broke section 6.3, found by 0055's failure
worker (roadmap item 0057). Each is now said in 6.3 and done by the runtime.

**A write to a pipe whose reader has gone is a write failure**, and the
host never stops the program for it. Before, the process was killed by
SIGPIPE: a program piped into `head -c 10` that saw its flush fail and
returned 3 exited 141, against 6.3's "a program that has been told of every
failure keeps the status it returned", and a `tee` that carried on to its
other files died silently with them half written. The runtime now ignores
SIGPIPE, so the write returns an error and 6.3's rules apply: reported, the
program keeps its status; unreported, it exits 70.

**A standard handle the host left closed is open on nothing.** A program
started with standard output closed (`prog OUT >&-`) gave the first file it
opened descriptor 1, so both outputs went into the file and every flush
said 0. 6.3 said the three handles are open from the start and was silent on
this. Now it says what happens: the handle is open, a read of it returns -5,
every byte written to it is lost and reported as a write failure, and no
file is ever given 0, 1, or 2. The runtime opens `/dev/null` in the other
direction on any of the three that is closed before the program starts, so
its reads or writes fail. GNU coreutils opens `/dev/null` the same way but
so that writes succeed; that would lose output with nothing told, which is
the failure 0018 was made to end.

**-3 means the host looked and found nothing.** `open_read` of a link to
itself and of a name over 255 bytes returned -3, "no such file", since the
runtime asked `access` whether the name existed and took any failure for
no. 6.3 now says -3 is for a name the host looked up and found nothing at,
a missing file or a missing directory on the way, and that a name it
cannot look up, too long or looping, is -5; `rename`'s missing source is
read the same way. A directory on the way that may not be searched now
gives `open_read` -4, permission denied, where it gave -3.

**What it cost.** The runtime had no errno, since the accessor's name
differs: `__error` on macOS, `__errno_location` on Linux, and its text must
be the same on every host. It now finds whichever `dlsym` has at startup,
and reads only the codes with the same number on both, ENOENT, ENOTDIR,
EACCES, and EPERM; ELOOP and ENAMETOOLONG differ, which is why the rule is
written as "found nothing" rather than as a list of failures. Without
either accessor it reads every name `access` cannot find as missing, as it
did before. Ignoring SIGPIPE is `signal(13, 1)`, the same numbers on both.
0062, typed failures for rename, flush, and close, will need errno for more
than this, and starts from here.

`tests/io/broken_pipe`, `tests/io/closed_std`, and more of
`tests/io/open_faults` show each; all three fail on the old runtime.

---

## Removing a key from a map no longer copies it, and no language change for it

**`map_remove` updates the map in place** (roadmap item 0056), as its doc
always said. The prelude's `map_shift`, which moves entries back over the
slot a removal empties, ended in

```
(map_shift (array_set ms i mj) ... n j (map_next j ms))
```

and `map_next` reads `ms` for its length. That read is a later operand of
the same call, so it still held the marks array when the first operand's
`array_set` ran, and every shift copied the whole array: the case section
6.5 names, of a read nested inside a later operand. The next slot is now
bound with `let` before anything is updated.

**Why.** 0055's LRU cache, a map of 10,000 keys with a removal per miss,
ran five times slower than with the fix; a 10,000-key window slid 200,000
steps copied the marks array 84,043 times, 2.75e9 words, and none with it.
`tests/io/map_remove_in_place` slides a 1,000-key window over 200,000 keys
and requires that nothing is copied; on the old prelude it copies 191,044
times. No other update in the library reads its array in a later operand.

**What it says about the trap.** This is the third time a read after an
`array_set` in the same expression has copied silently: 0028 found it in a
heap, and section 6.5 and both skills warned of it before the map was
written, by an author who knew the rule. Only `L0_ARRAY_STATS` shows it,
and no test fails. It waits, recorded in 0055, for a change that makes the
mistake impossible or visible rather than documented.

No rule in `spec/L0.md` changed.

---

## The compiler and the suite keep their tables in the library's map, and no language change for it

**The compiler's pad table is a `(Map (list int) Pad)`** (roadmap item
0054), where it was `PadMap`, a binary trie walked by twelve bits of
`sym_hash`, a polynomial string hash of its own, with a bucket at each end.
`pad_map`, `pad_of`, and `read_only_of` are three short functions over the
map, and `PadMap`, `sym_hash`, `pm_add`, `pm_bucket`, `pad_in`, and
`read_only_in` are gone. A symbol given twice keeps the later `Pad`, as the
trie's bucket did, since it consed the later one in front.

**`tests/io/array_paths/graph.l0` names its nodes in a `(Map (list int)
int)`**, where it had `NameMap`, the same kind of trie, with `name_hash`.
`array_paths.sh` already requires that no array update copies, and the
map's arrays are arrays, so the test shows the map updating in place inside
the `Graph` it is a field of.

**Why.** Each was a hash table written for one key type, the copy 0051
counted six times; the library's map (the entry below) is the one written
for every type.

**What it cost.** Nothing visible. The compiler emits the same bytes as the
compiler before it on its own source and on all 90 programs in
`tests/check`, `tests/lang`, and `tests/io`, checked against the seed it
replaced, and compiles itself in the same 0.17 s. Its IR shrank from
1,223,833 bytes to 1,218,590.

No rule in `spec/L0.md` changed.

---

## The prelude has a map for every key and value type

**`lib/prelude.l0` declares `(Map K V)`** (roadmap items 0051 and 0053),
with `map_put`, `map_get`, which returns an `Option`, `map_has`,
`map_remove`, `map_size`, `map_keys`, and `map_values`. It is an
open-addressing table in three arrays, at most half full, probed linearly
from `(mod (hash k) capacity)`, which `hash` (the entry below) makes
possible for a key of any type. Each update matches the map at its last
use, so its arrays have one holder and change in place, as section 6.5
says an array in a field does; a map something else still holds is copied
whole on its next update, as an array is.

**Why.** This repository wrote a hash table or trie six times, each for one
key type, the compiler's `PadMap` among them, and 0014's wordfreq used a
tree, 3.5 times slower than 0028's table. 0051 timed a table in arrays
against a persistent hash trie shaped like `PadMap`: on a million string
keys the table took 268 ms to put them and 128 ms to get them, the trie 742
and 1140, and every table this repository wrote is filled and then read,
which is the table's case. A persistent map, for code that keeps old
versions, waits for code that does.

**Choices made in writing it.**

- *The empty map is written with its types,* `((MapEmpty (list int)
  int))`, as `((None int))` is: a function cannot take a type argument, so
  there is no `map_new`. It holds no arrays, since there is no value of an
  unknown type to fill them with until the first key arrives
- *A slot holds a mark,* `(add (hash k) 1)`, never 0, so an empty slot is 0
  and most keys are told apart without `eq`, and a key's slot is always
  worked out from its mark. 0051's prototype placed a key by its hash but
  moved it by its mark when the table grew, and lost the key whose hash was
  0; there is one place now that turns a mark into a slot
- *Removal shifts the entries after the removed one back,* rather than
  leaving a tombstone, so lookups never pass a slot that holds nothing. The
  slot it empties may keep the removed key and value until it is reused,
  since a slot cannot be filled with nothing; when the map empties, its
  arrays go
- *`map_keys` and `map_values` list in slot order,* which `hash` decides,
  and since `hash` is specified the order is the same on every run and
  every host, though not the order of insertion

**What it costs.** Timed as 0051 timed its prototype, with the hash now the
builtin: 210 ms to put a million string keys and 322 ms to get them. The
prototype given the builtin `hash` in place of its own polynomial string
hash takes the same, 217 and 293: 0051's faster gets came from that weak
hash putting the benchmark's consecutive keys in consecutive slots, which a
mixed hash rightly does not. Hashing itself is faster as the builtin, 36 ms
for the million keys against 49 for the L0 loop.

No rule in `spec/L0.md` changed. The prelude is compiler source, so the
compiler is built with these definitions, though it does not use them yet
(0054 moves its pad table onto a `Map`). The compiler emits every copy of a
function with type parameters (10.2), four for each map function, so its IR
grew from 1,162,422 bytes to 1,223,833; every copy is internal, LLVM drops
the unused ones, and the compiler's binary and its speed are unchanged.

---

## `hash` gives a value of any type a specified integer

**`(hash x)` takes a value of any type and returns a non-negative `int`**
(sections 6, 6.9, 10.2, 10.3; roadmap items 0051 and 0052), the same for
two values `eq` calls the same. It is defined exactly: a value's items, read
from what it holds as `eq` reads it, folded with 64-bit FNV-1a's offset and
prime, then mixed with splitmix64's finalizer and shifted right once. The
runtime computes it in `@l0_hash(x, counted)`, which walks a value with
`@l0_equal`'s worklist and no recursion.

**The blocker.** No map can be written once for every key type. A function
with type parameters can keep, pass, and `eq` a `T`, and nothing more, so it
cannot compute the slot a key goes in:

```
(def (slot_of K) ((key K) (n int)) int
  (mod (hash key) n))
```

failed with `unknown function hash`. So this repository wrote the same
string hash seven times (`sym_hash` in the compiler, `name_hash` in four
programs, `hash_onto` in two) and a table or trie over it six times, and
0014's wordfreq used a tree instead, 3.5 times slower than 0028's table.
0051 weighed the alternatives.

**Why a builtin.** Hashing per key type, written in L0, is the copy being
removed, and an ordering with a tree is neither earned (0041 found the
orders here are mostly not structural) nor fast. Only the runtime can read
a value whose type the code does not know, from its block headers, as `eq`
already does.

**Why specified exactly.** A map lists its keys in slot order, which is the
hash's. Were the hash each implementation's own, one program could print
in one order here and another elsewhere, which section 10.4's determinism
is meant to rule out for a program as it does for the compiler. Specified,
a hash can be pinned in a test and stored in a file. The cost is that
changing it is a language change.

**Why these items.** A word alone does not say whether it is a pointer, and
a cons cell and a one-field data block can have the same header, so the
items follow one walk over blocks: every word of a block in order, a
pointer standing for the items of what it points to. That is what makes a
list's items its elements' then 0, and a data value's its tag, its fields,
and a 0 for each slot a wider constructor of its type has. Each value
contributes exactly what `eq` compares, so equal values hash alike.

**Why the mixing.** FNV-1a's multiply carries an item's low bits only
upward, so `(mod (hash x) n)` for a power of two `n` would see only the
items' low bits, and keys that differ above them, such as multiples of
1024, would share slots. splitmix64's finalizer folds the high bits down.
The last shift makes the result non-negative, so `mod` gives a slot
directly.

No program changes meaning: `hash` was not a builtin before, and a program
that defines a function `hash` keeps its own (section 7). Stage 0 does not
know it, so its tests are in the compiled suite. The compiler and the
prelude do not use it yet; the library's map (0053) will.

---

## Opening a file says which failure it was, and no language change for it

**`IoOpened` takes the type of its failures** (roadmap items 0049 and
0050): `(data (IoOpened E) (IoOpened IoFile) (IoFailed E (list int)))`.
`open_in` and `open_in_bytes` return an `(IoOpened OpenFault)`, whose cases
are `OpenMissing`, `OpenDenied`, and `OpenFailed`, and `open_out`,
`open_appending`, and `open_out_buffer` an `(IoOpened CreateFault)`, with
`CreateDenied` and `CreateFailed`: exactly the codes spec 6.3 lets each
open return. A failure carries its case, for code to test with `eq` or
`match`, and its words as before, for a message.

**Why.** A program told a missing file from one it may not read by comparing
words or a code, and the checker could say nothing of either. 0014's
kvstore compared `IoFailed`'s words with "no such file", which 0014 recorded
as a limit, since rewording the message would quietly turn every first `kv
set` into an error; kvlog compared them with `(io_error -3)`. Worse, a test
for a failure the call cannot produce type checked and never fired: 0048's
first draft expected `open_out` on a missing directory to say "no such
file", but spec 6.3 gives -3 only to `open_read` and `rename`. With a case
per kind of open, `(eq fault (OpenMissing))` after `open_out` is a type
error, `the second argument of eq must be CreateFault, but this is
OpenFault`. "Reading a line can report a failure" gave `IoLine` a code
rather than words for the same reason, and left `IoFailed` with words; this
finishes that for opening.

**Why not one failure type for every operation.** Its names would be real,
but the checker would still accept a case the open cannot give, so 0048's
mistake would still compile, and a complete `match` on a failure to create
a file would have to handle cases that cannot happen. Constructor names are
global within a group (7.1), so each type's cases carry its prefix.

**What it cost.** Every `IoFailed` arm names one more field, `((IoFailed
fault why) ...)`; the checker pointed at each of the 47 in the library and
the tests, and those that report keep `why` as it was. A program holding
an open's result writes its kind, `(IoOpened CreateFault)`; none here did
but the library. Reads, closes, flushes, and renames keep their codes, since
0049 found no program that tells their failures apart.

The builtins are unchanged and still return codes; `opened_in` and
`opened_out` in `lib/io.l0` are the one place an open's code becomes a case.
No rule in `spec/L0.md` changed.

---

## The compiler is written with type parameters and eq, and no language change for it

**The compiler's copies are gone** (roadmap item 0047). Its 19 per-type
`rev`, `length`, and `append` functions (`rev_decls_onto`, `length_tys`,
`append_sigs`, and the rest) are calls to the prelude's generic ones. It
compares with `eq` where it called `list_eq` 73 times, and where it had
written `ty_eq`, `tys_eq`, and `bools_eq`, which compared exactly what `eq`
compares, since a `Ty` holds no positions. The checker's `FindSig`,
`FindTy`, `FindCtor`, and `FindData` are `Option`. Its `CTy`, `CTys`, and
`Binds` are one `(Checked T)`, and the parser's nine result types, `PTy`
through `PDecl`, are one `(Parsed T)`; with that, `parse_arm` and
`parse_ctor` return an arm and a constructor rather than a list of one,
which they did only to share a list's result type.

**Why `Checked` and `Parsed`, not `Result`.** Each carries two fields where
`Result`'s constructors carry one: a parser's success is a value and the
tokens after it, and every failure is an offset and a message. As a
`Result`, every error would be built as `(D o m)` inside an `Err` and taken
apart by a second `match`, since patterns are one level deep, and the
parser's successes would need a pair type the library does not have. A
failure is built as `((CErr Ty) o m)` or `((PErr Expr) o m)`, its type
written as `None`'s is, and matched as `((CErr o m) ...)`.

**What it cost.** Nothing visible: the compiler emits the same bytes as
before on its own source and on every program and failing program in
`tests/lang`, `tests/check`, and `tests/io` (checked against the seed it
replaced), and compiles itself in the same 0.15 s. Its IR shrank from
1,167,452 bytes to 1,157,183, and its source by 149 lines.

No rule in `spec/L0.md` changed.

---

## The prelude takes back the generic definitions, and no language change for it

**`lib/prelude.l0` holds every definition that does no I/O** (roadmap item
0046): `rev_onto`, `rev`, `append`, `length`, `any_eq`, `index_of`,
`array_resize`, `Option`, and `Result` moved there from `lib/io.l0`, which
now holds only I/O. Programs see no change, since `tools/l0` links both
files as one prelude group. The compiler, which is built from
`lib/prelude.l0`, now calls these at the types it needs: its `(list int)`
copies of the first six at the top of `compiler/lex.l0` are gone, and so is
the prelude's `rev_strs_onto`, the copy of `rev_onto` that `split_spaces`
and the parser used for lists of strings.

**Why.** The split was never about I/O. Stage 0 ran `lib/prelude.l0` as part
of the compiler, and knew neither type parameters nor `eq` on lists, so
whatever used them went to `lib/io.l0` (the entry "The library declares
Option and Result" gave that reason, which this supersedes). Since stage 0
no longer runs the compiler's source (the entry below), the reason is gone,
and the split can mean what the file names say. A generic `rev` also cannot
sit beside a `(list int)` one in a group, so while the definitions were in
`lib/io.l0` the compiler had to keep its own under the same names.

**What it cost.** The compiler compares names with `eq` inside `any_eq` and
`index_of`, which at `(list int)` calls the runtime's `l0_equal` rather
than a loop of its own, and instantiates `rev` at each type it reverses.
The compiler's IR grew from 1,162,096 bytes to 1,167,452.

No rule in `spec/L0.md` changed.

---

## The compiler's source is no longer run by stage 0, and no language change for it

**The tools build the compiler with the seed** (roadmap items 0044 and
0045). `tools/compiler.sh` compiles the current `lib/prelude.l0` and
`compiler/*.l0` once with `bootstrap/stage2.ll`, links the result at `-O0`,
and keeps it in `build/l0c-current` with the bundle it was built from,
rebuilding when that bundle, the seed, or the runtime changes.
`tools/l0check`, `tools/l0c`, and the compiler's stage tests in
`tools/test.sh` run it. Before, all three ran the compiler's source under
the stage-0 interpreter, and the bootstrap could start from stage 0 when
there was no seed; that start is gone.

**Why.** Stage 0 knows only the L0 of its day, so running the compiler's
source under it held the compiler and the prelude to that L0. Every feature
since arrays paid for it: the compiler keeps a `(list int)` `rev`,
`length`, `append`, `any_eq`, and `index_of` of its own, 19 more per-type
copies, 75 calls to `list_eq`, and nine result types of one `Result` or
`Option` shape, and the library is split between `lib/prelude.l0` and
`lib/io.l0` by what stage 0 can run rather than by topic. The seed already
compiles type parameters and `eq` on any type, and a compiler whose helpers
use them bootstraps to a fixpoint from it (0044's prototype), so only the
tools stood in the way.

**What it cost.** Nothing in checking: the native checker takes 0.4 s to
build after a change to the compiler's source, and checks the compiler's own
source in 0.25 s where stage 0 took 0.8 s. The stage tests each build the
whole compiler now, so they are built and run at once, and `tools/test.sh`
takes about 10 s where it took 6. In independence, one comparison: stage 0
ran the compiler's code on the 14 stage tests' inputs, and the compiled
compiler had to agree. Their goldens were the compiler's own output either
way, since stage 0 only ran the compiler's checker and emitter, so they are
blessed as before, by `tools/test.sh --bless`, and `--compiled` still runs
them through the bootstrapped compiler. Stage 0 keeps the judgment it is
there for: it runs the programs of `tests/lang` and `tests/check`, and the
compiler's output on them must agree with it.

**What else changed.** `tools/l0c` no longer runs a `build/l0c-native` left
by an earlier `--compiled` run, which after a compiler edit silently ran the
previous compiler. A compiler source that uses a feature the seed predates,
the mistake the two-step rule guards against, now fails the next
`tools/l0check` with the seed's diagnostics, rather than the next bootstrap
or only a fresh clone.

No rule in `spec/L0.md` changed.

---

## The library compares with eq, and no language change for it

**`any_eq` and `index_of` take a value and a list of any type** (roadmap
item 0043), under the same names, in `lib/io.l0`. They compare with `eq`,
so `(any_eq 3 xs)` and `(index_of (Some 2) os)` work as `(any_eq "if"
words)` always did. `lib/test.l0`'s `check_str`, `check_strs`, and
`check_bool` compare with `eq` too, and `strs_eq`, its copy of `list_eq` one
level up, is gone. The suite's programs (kvlog, graph.l0, write_failure,
array_myers, csvcol_test) call `eq` in place of `list_eq`.

**Why the same names, and what that cost.** As for `rev` in 0040: a generic
`any_eq` cannot sit beside the prelude's in one group, and the prelude
cannot hold one while stage 0 runs it. So the two left `lib/prelude.l0`, and
the compiler, which calls them about 57 times on names, keeps its string
copies at the top of `compiler/lex.l0` beside its `rev`. The argument order
is unchanged, the value first and the list second, so no call changed.

**Why `list_eq` stays.** The prelude and the compiler compare strings with
it about 70 times, and stage 0's `eq` takes only integers. Its
documentation says a program can write `eq`.

No rule in `spec/L0.md` changed.

---

## `eq` compares two values of any type

**`(eq a b)` takes two values of any one type** (sections 4.1, 6, 6.6,
6.8, 10.1, 10.2, 10.3), and is true when they hold the same thing: equal
integers or bools, lists and arrays of the same length with the same
elements, bytes with the same bytes, and data values built with the same
constructor from the same fields. Never by address. `lt`, `le`, `gt`, and
`ge` stay int-only. At `int` and `bool` it is the `icmp eq` it always was.
At any other type it calls the new runtime function `@l0_equal`, which
walks both values from their block headers with a worklist of its own, so
neither a long list nor a deep nesting uses stack.

**The blocker.** Roadmap item 0041 found that a function with type
parameters cannot compare its elements:

```
(def (member T) ((x T) (xs (list T))) bool
  (if (is_empty xs)
      false
      (if (eq x (head xs)) true (member x (tail xs)))))
```

The checker rejected it with `an argument of eq must be int, but this is
T`. So every membership test, lookup, and equality over anything but `int`
was written once per type. 0041 counted about 47 such functions in the
library, the suite, and the compiler: `list_eq`, `strs_eq`, `bools_eq`,
`ty_eq`, `any_eq`, `index_of`, and the lookups, sets, and duplicate checks
built on them. With no function values, nothing could be passed in to do
the comparing.

**Why `eq` itself, rather than a new name.** No program changes meaning,
since `eq` on anything but `int` was an error. A separate `equal` would
leave two names for one idea, and an agent writing `(eq s t)` on two
strings would still get a type error and have to find the other name. That
is the trap 0040 avoided by keeping `rev` and `length` under their own names.
A program that defines its own `eq` still calls its own (section 7).

**Why structural equality, decided at run time.** A function with type
parameters compiles to one copy per counted-or-not combination (10.2), so
inside a copy the compiler knows only whether a value is a pointer, not its
type. Code chosen per type at compile time cannot be written there. The
block headers can do it:
- the mask says which words are pointers, and a data block's tag is word 0
- a data block is cleared when it is made, so the words past a narrower
  constructor's fields are 0, which 10.1 now promises
- the empty list is 0, and no other value is

The v1 reason for keeping `eq` int-only (below, in the v1 entry) was that
the one-word representation keeps no type information. Headers, added for
reference counting, brought back almost all of it.

The one gap was bytes. A bytes block had exactly the header of an `(array
int)` of the same length, and its length word counts bytes where the
array's counts words. Bytes now have mask bit 1, which no array has, and
every array path in the runtime reads only bit 0, so freeing and copying
are unchanged.

**The rejected answers.**
- *A constraint on a type parameter saying it can be compared*, with code
  chosen per type, needs a hidden argument or a copy per type. The entry
  for type parameters already rejected both, and while every L0 type can be
  compared, such a constraint would say nothing.
- *Function values* give up purely syntactic name resolution and need an
  exception to the tail-call guarantee. Without closures, comparisons do not
  compose either: comparing `(list (list int))` would still need a function
  written for that type. They remain the answer for comparisons that are not
  structural, such as by one field or case-insensitively, and are a separate
  question.
- *Structural ordering and hashing*, a `compare` and a `hash`, use the same
  walk, but 0041 found that most ordering in the programs here is not
  structural (wordfreq sorts by count, then word). A `compare` would also
  make the order of constructors in a declaration observable, so it waits
  for a program that needs it. A `hash` must be specified exactly, or a
  program's output would change between versions of L0. One string-keyed
  hash trie written four times earns it, as a later item.

**What it costs.** `eq` on lists, data, arrays, or bytes takes time in
proportion to how much of the two values it examines, where it took
constant time before only on `int`. That is the cost every `list_eq`
already paid. `eq` reads without consuming, as `is_empty` does, so a
parameter used only in an `eq` stays read-only (10.3). The compiler's own
output gains one declaration and nothing else, since every `eq` in it is on
`int`. Stage 0 still rejects `eq` on anything but `int`, so the compiler
and `lib/prelude.l0` cannot use it while stage 0 runs them, and its tests
are in the compiled suite.

---

## The library's list helpers take every element type, and no language change for it

**`rev`, `rev_onto`, `append`, and `length` take a list of any type, and
`array_resize` grows or shrinks an array of any type** (roadmap item 0040).
The first four were in `lib/prelude.l0` for `(list int)` only, and are now
in `lib/io.l0` with type parameters, under the same names. `array_resize a
n fill` is new: the first `n` elements of `a`, then copies of `fill`.

**Why the same names, and what that cost.** A generic `rev` cannot sit
beside the prelude's in one group, and the prelude cannot hold a generic one,
since stage 0 runs it as part of the compiler. The other answer was new
names in `lib/io.l0`, leaving the prelude alone. That would have kept two
names for one thing forever, and an agent writing `(rev toks)` for a list of
tokens would still get a type error and have to look up the other name,
which is the mistake 0038 set out to end. So the four left the prelude, and
the compiler, which calls them about 200 times and cannot use type
parameters while stage 0 runs it, keeps `(list int)` copies at the top of
`compiler/lex.l0`. Every build and stage test of the compiler includes that
file, so none of their file lists changed. The prelude still calls `rev` and
`append`, and finds them in `lib/io.l0` in a program's prelude group and in
`compiler/lex.l0` in the compiler. The cost is that `lib/prelude.l0` no
longer checks by itself. Only `tests/io/parametric_data` listed it alone, and
it now lists `lib/io.l0` too.

**Why these five.** 0035 counted reversing, length, appending, indexing, and
growing an array as the helpers rewritten per element type. The suite's own
programs had three of them: kvlog's `rev_entries`, array_paths' `count_fields`,
and graph's `copy_into`, an array grow. All three are gone, and graph's
`rev_strs_onto` call is now `rev` too. No program here indexes a list, so
there is no `nth`. Anything that compares elements, such as `strs_eq` in
`lib/test.l0` or `list_eq`, stays per type, since `eq` takes only `int`.
`rev_strs_onto` stays in the prelude, which `split_spaces` needs, but is no
longer documented, since `rev_onto` does its job for programs. Helpers over
`Option`, which the entry for 0039 said 0038 would make possible, wait for a
program that wants them.

**`l0 doc` reads a parenthesized head.** It took the name of a declaration
to be the word after `def` or `data`, so for `(def (rev T) ...)` it found
none. `l0 doc Option` only worked because `Option` was mistaken for a
constructor. It now takes the first word inside the head, and shows the head
as written, `(rev T) ((xs (list T))) (list T)`.

No rule in `spec/L0.md` changed.

---

## Functions take type parameters

**A `def` may take type parameters** (sections 3, 4, 4.1, 5.7, 9, 10.2,
10.3): `(def (rev_onto T) ((xs (list T)) (acc (list T))) (list T) ...)`.
Within the declaration each type parameter is a type of its own, equal only
to itself, so the body is checked once and is correct at every type. A call
finds what each type parameter stands for by matching its arguments' types
against the parameters' types, one way and left to right, as a construction
does against its fields. Every type parameter must be mentioned by some
parameter's type, so every call determines them all. `main` takes none.
Each function compiles to one copy per combination of whether its type
parameters stand for counted types, named `@l0_f_rev_onto.0` and `.1`.

**The blocker.** Roadmap item 0035 found that most of the code written for
want of generics is helpers, not declarations: the compiler's `rev_*_onto`,
`length_*`, `append_*`, and `find_*` walks, about 100 lines, one per element
type; the prelude's `rev`, `length`, and `append` for `(list int)` only,
with `rev_strs_onto` beside them and `strs_eq` in `lib/test.l0`; kvlog's
`rev_entries`; array grow helpers rewritten in five 0028 programs. 0036 and
0039 removed the duplicated declarations, and none of these. What could not
be written was the first line of the example above, which the checker
rejected with `expected a function name after def`.

**Why every type parameter must appear in a parameter's type.** Then a call
needs nothing written: its arguments already have complete types, and one-way
matching against the parameters is the rule 5.6 gave constructions, so "every
expression's type is determined by its parts" still holds with no inference
and no unification. A function whose result alone mentions a type
parameter, such as one that builds `((Err T (list int)) why)`, would need
the types written at each call, as `((None int))` writes them. No program
here needs one yet, and the rule can be relaxed later without changing the
meaning of any program that compiles now; the form for writing them,
`((f int) x)`, is free, since `((` followed by a lower name begins nothing.

**Why a type parameter is a type of its own.** The alternative, checking a
body once per type it is called at, would make whether a function is correct
depend on its callers, and would report an error inside a library function
at a program's call. A type equal only to itself is the smallest rule that
lets the body be checked alone: a value of it can go anywhere that takes
every type, and nowhere that takes one. The cost is that a generic function
cannot compare its elements, since `eq` takes only `int`; with no function
values, a sort or a map over keys is still written per key type.

**Why one copy per counted-or-not combination.** 0035 found that compiled
code asks only one thing of a type: whether its values are counted, which
decides a block's mask, whether a use adds a reference, and whether a read
yields a pointer. Every copy of a combination asks the same questions and
gets the same answers whatever the actual types, so it is correct for all of
them. The other answers were a hidden argument carrying the bit, which would
make counting a test at run time and thread a value through every call, or a
copy per actual type, which multiplies code by the types a program uses
rather than by at most two per parameter. The copies are separate functions
to the read-only analysis and the tail-call padding, since a parameter that
is read-only when `T` is `int` may not be when `T` is a list: `(head xs)`
yields a pointer only then.

**How it is compiled.** A pass between checking and emitting, run only when
some function takes type parameters, replaces each such function by its
copies, with each type parameter replaced by `int` or by `(list int)`, which
stand for their kinds, and renames each call to one of them to the copy its
arguments' types choose. The emitter and the runtime are unchanged, and so
is everything compiled from a program that uses no type parameters, the
compiler among them.

**What is given up.** Of the properties the l0-bootstrap skill lists,
"functions do not take type parameters" is gone. "No type inference" and "no
unification anywhere" hold, and so does purely syntactic name resolution.

**Where it can be used.** Stage 0 cannot parse it, so `lib/prelude.l0` and
the compiler do not use it, and its tests are in the compiled suite. The
library's list helpers are the first code it makes possible, and are a
separate item, since the prelude's `rev` and `length` already take the names
and stage 0 runs the prelude.

---

## The library declares Option and Result, and no language change for it

**`lib/io.l0` declares `(Option T)`, with `None` and `Some`, and `(Result T
E)`, with `Ok` and `Err`** (roadmap item 0039), exactly as section 4's
examples write them. Every program now has both without declaring them, and
one that declares its own `Ok` or `Some` keeps its own (7.1).

**Why these two and no pair.** About ten one-use types across 0014, 0028,
and the suite are a value or a failure, such as calc's `Lexed`, life's
`Parsed`, and kvlog's `Loaded`, and two more, kvstore's `Lookup` and
linediff's `Found`, are a value or nothing; those are the shapes that recur
with nothing to name. A pair does not recur that
way: every two-value type here, `Split`, `Updated`, `Interned`, `PJ`'s
fields, has a name that says what its halves are, and `(Pair Graph int)`
would say less. A pair waits for a program that wants an array or list of
them, which dijkstra's heap would be.

**Why `E` is a parameter rather than always a message.** Most errors here
are a `(list int)` in words, and fixing `E` to that would let `(Ok x)`
take its type from `x`. But the library's own failures carry an `int` code
(section 6.3), and a `Result` that cannot hold one would not serve the
library it lives in. The cost is that neither constructor determines both
parameters, so every `Ok` and `Err` is written with its type, as in
`((Ok (list Entry) (list int)) es)`. That is the price section 5.6 already
names, and parametric functions would not lower it, since a helper making an
`Err` still has a `T` nothing determines.

**Why the `Io` types do not become `Result`s.** `IoLine` has three cases,
and `IoOpened` and `IoBytes` are matched by name in every program that opens
or reads a file. Recasting them would break all of those programs to save no
line in the library.

**Why no helpers.** Functions do not take type parameters, so an `is_some`
or `unwrap_or` would be one function per element type, and the library
cannot know which types programs use. They are the first library functions
0038 would make possible.

**Why `lib/io.l0`, though they are not I/O.** Stage 0 runs
`lib/prelude.l0` and does not know type parameters, so the prelude cannot
hold them, and `lib/io.l0` is the library stage 0 does not run. A new file
would have to be named in `tools/l0`, `tools/bundle.sh`, the install
layout, and the sixteen `.extra` files that list `lib/io.l0`, all to change
one heading of `l0 doc`. The file's header now says that what stage 0
cannot run, not I/O, decides what goes in it.

**What moved onto them.** `lib/examples.l0` shows the library's `Option` in
place of its own `Maybe`, and `parse_number` shows a `Result`; its `Parsed`
renames `Ok` to `Num`, so the examples no longer shadow the library they
teach. `tests/unit/kvlog.l0` drops `Loaded` and `Lookup`, so `kv_get`
returns a `(Result (Option (list int)) (list int))`.
`tests/unit/shadow_test.l0` declares its own `Ok` beside the library's and
uses the library's `Option` in the same program. 0014's calc and 0028's json
declare `Err` and `Ok` of their own, and still pass their tests unchanged.

No rule in `spec/L0.md` changed.

---

## A program's types shadow the library's, and Io names are no longer reserved

**Type and constructor names resolve per group, as function names do**
(sections 4, 7, 7.1). In a program declaration an upper name is the
program's type or constructor if the program declares one, and otherwise
the prelude's; in a prelude declaration it is only ever the prelude's. Two
same-named types, one per group, are different types. **The `Io` prefix is
no longer reserved**: a program may declare `IoFile`, and then has its own.
Every program that compiled before still compiles; the only program this
rejects is one whose prelude names a type only the program declares, and no
prelude here does.

**The blocker.** 0036 made one `Option` or `Result` serve every element
type, and the library is where one belongs. But type names were global
across the prelude and the program, and twelve files here already declare
`Ok`, `Some`, `Pair`, or the like, among them 0014's calc, 0028's json,
kvstore's tests, `tests/lang/last_use.l0`, and `lib/examples.l0`. Adding
those names to `lib/io.l0` would have broken all of them with "constructor
Ok is already declared", which is the breakage 0031 removed for builtins.
The `Io` reservation was the only way around it, which would have named the
shared types `IoOption` and `IoResult`.

**Why grouping, when it was weighed and rejected before.** "Files,
arguments, and names reserved for the standard library" weighed the same
three answers with the user and chose the reservation, because grouping
looked like it would touch about 44 resolution sites and override the two
reasons 7.1 gave for global names. Neither holds:

- 7.1's first reason was that a `match` arm names a constructor without its
  type, so resolution had to be global for one-level patterns to resolve.
  Per-group resolution keeps that property: within one group a constructor
  name still denotes exactly one constructor, so an arm still determines
  its constructor alone
- the second was that a checker comparing types by name could not tell two
  same-named types apart. It does not need to. Before checking, one pass
  renames every type and constructor in the prelude's declarations that the
  program also declares to a name no source can write (the prelude's `Ok`
  becomes `prelude's Ok`). The two are then different names, the checker
  and emitter compare by name exactly as before, and none of the 44 sites
  changed. A prelude reference to a type only the program declares is
  renamed the same way and reported as unknown, which is 7.1's rule that the
  prelude cannot see the program
- the reservation also asked every later library area for a prefix of its
  own, each a breaking change once; grouping makes adding any library type
  a breaking change never

The cost is what shadowing a function already cost: a program that declares
its own `Ok` cannot build or match on the library's, and since a `match`
names every constructor, cannot take the library's type apart at all. It can
still hold and pass on the library's values. The renamed name appears in
diagnostics, as in "but this is prelude's Result", which says which type it
is.

**Why the reservation goes rather than staying beside grouping.** It
existed so the library could gain types without breaking programs, and
grouping now guarantees that for every name. Kept, it would be a rule with
no remaining reason, and the reason a reader could tell the library's types
by name is kept anyway by the library's own convention: `lib/io.l0` still
names its types `IoLine`, `IoFile`, and so on.

**Stage 0 is unchanged.** It still resolves type names globally and still
rejects `Io` names in a program, so a program that shadows a prelude type is
tested only in the compiled suite (`tests/io/shadow_types`), and the
checker's verdicts on grouping in a stage test (`tests/compiler/groups`)
that gives bundles to the compiler as data.

---

## Data types take type parameters

**A `data` declaration may take type parameters** (sections 3, 4, 5.5, 5.6):
`(data (Option T) (None) (Some T))` declares `Option`, and `(Option int)`
and `(Option (list int))` are types. A `match` binds each field at its
declared type with the subject's arguments in place of the parameters. A
construction finds its type from its arguments, `(Some 5)` being an
`(Option int)`; one whose fields do not mention every parameter, such as
`None`, is written with the type's arguments: `((None int))`. Functions do
not take type parameters, so every expression still has a complete type.

**The blocker.** A program needing "a value or an error", "a value or
nothing", or "two values" declared a new type for each type it held.
Roadmap item 0035 counted them: the compiler has ten result types of one
shape (`PTy` to `PDecl` in `parse.l0`, `CTy` and `CTys`) and four option
types (`FindSig` to `FindData`); 0014's json has `PJ` and `PS` and a
function that only moves an error from one to the other; kvstore has five
result types; 0028's mst has `UF` and `Found`; dijkstra interleaves its
heap in one `(array int)` "since there is no pair type to make an array of".
What could not be written was `(data (Option T) ...)`, which the checker
rejected with `a data declaration needs an uppercase type name`.

**Why data first, and functions not yet.** 0035 found that the only thing
compiled code needs to know about a type is whether its values are counted:
every value is an `i64`, freeing walks the mask in each block's header, and
the compiler's every counting decision goes through one predicate on the
static type. With functions kept monomorphic, every expression in every
function has a complete type, so each construction knows its field types and
each `match` knows its bindings' types, and nothing is compiled twice or
decided at run time. The runtime is unchanged. Parametric functions remove
more lines (0035: most of what is duplicated is helpers, not declarations),
but need a rule for compiling one function at several representations, and
are roadmap item 0038, to be earned by programs that use this first.

**Why a construction's type comes from its arguments.** It is the rule
`cons` already follows, taking its type from the list it is given, so
"every expression's type is determined by itself and its parts" (5.4)
still holds, and no inference or unification is needed: an argument's type
is complete, and is matched one way against the field's declared type. A
constructor whose fields leave a parameter out has nothing to take it from,
which is the case `nil` has, and is solved the way `nil` solves it, by
writing the type.

**Why `((None int))`.** The type has to be written somewhere the parser can
tell from an argument. `(None int)` cannot be: `(None (Pair int bool))`
would read as constructing a `Pair`, and `bytes` is a type and a variable
name both. `((` begins no expression today, so `((Ok int (list int)) 5)` is
unambiguous without knowing which names are types, and every argument after
the head is an ordinary expression. A new reserved word such as `the` would
have taken a name from programs, which section 7 does not do. The form is
allowed for any constructor of a parametric type, so a program can write the
type where it helps a reader, and refused for one without parameters, where
it could only be noise.

**Why a parameter hides a data type of the same name.** A reader can tell
what a field type means from the declaration alone. Forbidding the clash
instead would let a type declared elsewhere, perhaps later in the library,
break a declaration that never mentions it.

**What is given up.** Of the properties the l0-bootstrap skill lists,
"`list` and `array` are the only parametric type constructors" no longer
holds. "No type inference" and "no unification anywhere" do, and so do
one-level patterns and exhaustive `match`: an arm names a constructor, and a
constructor still belongs to exactly one type.

**Where it can be used.** Stage 0 is frozen and does not know the syntax,
so programs using it run in the compiled suite only (`tests/io`). The
compiler and `lib/prelude.l0` do not use it, since the interpreted suite
runs both under stage 0; adopting it there is a separate decision. The
library can use it in `lib/io.l0` and `lib/test.l0`, but not yet with names
programs already use, such as `Ok` or `Some`: type and constructor names are
not grouped (7.1), which is roadmap item 0037.

---

## Runtime error messages are specified, and stale references fixed

**Section 8 now gives each runtime error its message,** and the line it is
written in: `l0: runtime error: ` and the message. The seven a builtin raises
are in a table, and the three the host raises, `stack exhausted`, `heap
exhausted`, and `write failed`, are named where they are described. "There
are exactly seven runtime errors" had become false by that section's own
next paragraphs, which reported three more in the same form.

**Why the messages belong in the spec.** `l0 test` passes a test with an
`expect_NAME` only if standard error is exactly `l0: runtime error:` and the
message `expect_NAME` returns. An agent outside this repository has the
spec, `l0 doc`, and the examples, but not `runtime/l0rt.ll`, so it could
learn one message, from the skill's example, and had to guess the other
nine. The messages are the ones the runtime and stage 0 already write, so
neither implementation changed.

**Editorial fixes, with no change to the language.** The expression grammar
labelled literals with sections 3.1 to 3.3, which do not exist. Section 5.5
listed `int`, `bool`, and lists as invalid `match` subjects, omitting arrays
and `bytes`. Section 6.3 pointed at `lib/io.l0`, a path an installed
project does not have, where `l0 doc IoOpened` works everywhere. The title
said "v1" though the language has changed a great deal since, which left a
reader unsure which language it described; it now says the changelog, not a
version number, records change. "There is no other documentation" was false
for an agent with `l0 doc` and the examples; there is no other
*specification*.

---

## A clock

**A new builtin, `clock_ns`** (section 6.7): nanoseconds on a monotonic
clock, never negative and never decreasing while the program runs, or -5 if
the host has none. Only differences between readings mean anything. Reading
it is an effect, which section 8 now names beside I/O as something an
implementation may not move or remove.

**The blocker.** No L0 program could tell how long anything took, so every
timing in the repository was taken from outside, and finding where a program
spent its time meant building it once per stage. Roadmap item 0028's sort was
cut off after each stage by `roadmap/0028/text/exp/stage.l0` and each cut
timed by the shell and subtracted; its mst needed three extra programs for
the same (`roadmap/0028/algorithms/mst/bench/`); 0014's kvstore measured one
process per operation. With the clock, one run reports each stage.

**Why monotonic, and only that.** Every use so far is a duration, and a wall
clock is wrong for durations, since it jumps when the system's time is set.
A date is a different builtin, with its own questions (time zones, leap
seconds), and waits for a program that needs one.

**Why nanoseconds in an int.** An int holds 292 years of nanoseconds, so
there is no unit to choose per use and no overflow in any run, and the name
says the unit so that no reader has to look it up.

**Why no promise about where it starts, or how fine it is.** Hosts differ in
both, and a program that needs either is comparing readings across runs or
machines, which a monotonic clock cannot support anyway. The one promise
beyond order, never negative, is what lets -5 mean the clock could not be
read.

**How the runtime reads it on every host with one text.** The runtime must
not depend on anything whose shape differs between operating systems.
`clock_gettime` is the POSIX call, but `CLOCK_MONOTONIC` is 1 on Linux and 6
on macOS, and on Linux 6 is a coarse clock rather than an invalid one, so no
fallback order is safe. `CLOCK_MONOTONIC_RAW` is 4 on both, and `struct
timespec` is two 64-bit words on both, so the runtime asks for clock 4. The
raw clock is also not slewed by time synchronization, so a difference is
the time the hardware counted. It keeps counting while the machine sleeps on
macOS and stops on Linux, which is why section 6.7 leaves that to the host.

**Why not in the library, or a timing helper.** A clock cannot be written in
L0; a helper that formats a duration can, and none is added until two
programs want the same one.

---

## The library reads a whole input into bytes, and no language change for it

**`lib/io.l0` gains `read_input`, `file_read_all`, and `file_write_bytes`,**
and a result type, `IoBytes`: `(IoBytes b)`, or `(IoReadFailed code)` with
the code of section 6.3. `read_input` reads what is left of standard input
and `file_read_all` what is left of an `IoFile`, each with `read_bytes` and
then one `read_from` to learn whether reading stopped at the end or on a
failure, which is the check every program that calls `read_bytes` would
otherwise have to remember (roadmap item 0033). `file_write_bytes` is
`write_bytes` on an `IoFile`, as `file_write_str` is `write_str`.

**Why a failure drops the bytes read before it.** There is no pair type, so
one value carries either the bytes or the code, as `IoLine` does. A program
that reads a whole input to work on it has no use for part of one, and one
that wants to keep going past a failure can call `read_bytes` itself. There
is no end case, as `IoLine` has: an input that is already at its end gives
empty bytes, which is not an error.

**Why these names.** `read_input` mirrors `read_line`, and `file_read_all`
and `file_write_bytes` follow the `file_` names of the others. None is a
builtin's name, so none hides a builtin. 0026's prototypes of json and
sort each defined their own `read_input`; a program that still does keeps
its own, since 0031, and these now use the library's.

**What moved onto it.** `lib/test.l0` reads a golden file with
`file_read_all`, so a failed read is reported as one rather than looking
like a short file. `lib/examples.l0` has worked examples of arrays and
bytes. Roadmap item 0028's json and sort read their input with
`read_input` and hold it as bytes, and wordfreq holds its keys as bytes and
writes them with `file_write_bytes`: json on 11.5 MB peaks at 13.6 MB,
from 257 MB, and sort on 10 MB at 17.6 MB, from 260 MB, in about a third
to a half of the time. Their READMEs have the tables. Comparing ranges of
bytes is written twice, in sort and wordfreq, in two shapes, so it is left
out of the library until a third program shows which shape it should take.

`lib/prelude.l0` is unchanged, since stage 0 runs it and cannot run bytes.
No rule in `spec/L0.md` changed; this is recorded because `IoBytes` is a
choice between a result type and the handle state that a later reader
would otherwise have to guess.

---

## Bytes, held one byte per byte

**A new type, `bytes`, and six builtins** (sections 3 and 6.6):
`read_bytes` reads everything left on a handle, `bytes_len` and `bytes_get`
read it, `bytes_from_list` and `bytes_to_list` convert, and `write_bytes`
writes a range to a handle. A bytes value is immutable and takes about one
byte per byte. `bytes` is a type name but not a reserved word (section 2.3),
and the runtime errors are now seven, the new one an index out of range for
`bytes_get` or `write_bytes`.

**The blocker.** Roadmap item 0028's json and sort held their input as an
array and still peaked at 25 bytes per input byte: 257 MB for an 11.5 MB
JSON document and 260 MB for 10 MB of lines, against Python's 18 MB
(`roadmap/0028/text/limits/01-input-into-array.l0`). A program cannot learn
its input's length before reading it, so the array doubles, and the last
doubling holds both copies. Item 0026 prototyped both answers on the
programs themselves (`roadmap/0026/bench/`): a builtin reading all of a
handle into an `(array int)` of exactly the right size got json to 102 MB,
9 bytes a byte, since an int array costs a word a byte; packed bytes got it
to 13.6 MB and sort to 17.6 MB, and made sort three times faster, 0.25 s to
0.08 s, because it touches an eighth of the memory. Words kept as hash keys
in wordfreq went from 54 MB to 25.

**Why a type, not only the input builtin.** The input builtin alone fixes
the doubling and nothing else. With bytes, a program that wants an int
array builds one from them in L0, so the builtin that reads into an array
is not needed at all and was dropped.

**Why these six, and no more.** They are what the three programs needed.
sort compares lines with `bytes_get` in L0 and is still three times faster;
wordfreq hashes its words in L0; json only reads. Slices, comparison,
hashing, update, and literals were each left out because no program needed
them, and each can be added the day one does, now that a new builtin breaks
nothing (the entry below). String literals stay lists, and
`bytes_from_list` is how one becomes bytes.

**Why the names.** `bytes_len` and `bytes_get` mirror `array_len` and
`array_get`, and `read_bytes` and `write_bytes` mirror `read_byte` and
`write_byte`. The prototype had to call them `byte_at` and `bytes_write`,
because `write_bytes` and others were taken by existing programs; the
entry below is what made the natural names safe. None of them is a name
the standard library defines, which would hide the builtin from every
program the library is linked with.

**Why `read_bytes` has no error result.** It returns bytes, and there is no
pair type to return a code alongside them. The handle's state already
records why reading stopped, so the next `read_from` says -1 for the end or
-5 for a failure, as it would after reading byte by byte. `lib/io.l0` will
wrap this in a result type (roadmap item 0033), which it can only do once
the seed knows the type.

**Why `bytes` is not reserved.** Every other lower type name is. But
`bytes` arrived after programs had used it, as a parameter in 0028's sort
and wordfreq tests, and taking it would break them for no gain: the parser knows
a type position from its place, so a type name needs no reservation to be
read unambiguously. The same reasoning is why a new builtin no longer takes
over a function (below).

**Why the conversions consume their argument.** Section 10.3 says the
compiler adds a reference to what a builtin that reads without consuming
returns, because until now every such result was a part of the argument.
`bytes_to_list` returns a new list, and adding a reference to it would leak
it. Consuming is what any function does, and costs a program nothing it can
see. The builtins that do read without consuming, `bytes_len`, `bytes_get`,
and `write_bytes`, return ints, so a loop over a read-only bytes parameter
stays a tail call with no reference counting per step.

**The layout.** A bytes block has an array's header, with no pointer
elements, then the bytes, so the code that frees arrays frees bytes, and
`L0_RC_CHECK` and the live count needed nothing new. `read_bytes` reads
into a buffer that doubles and is trimmed, and that buffer becomes the
block, so its peak is about the input's size.

**What it costs.** One more type, not parametric, so `list` and `array` stay
the only type constructors with a parameter and no builtin needs
unification. Nothing is mutable. Stage 0 cannot run any of it, as with
arrays, so the new builtins are tested by the compiled suite alone, against
expectations written by hand; the compiler does not use them, so this is one
bootstrapped change.

---

## A new builtin does not take over a program's function

**A `def` now shadows a builtin of the same name** (section 7): a call
resolves to a builtin only when no `def` of that name is visible to it,
under section 7.1's rules when there is a prelude. It used to be the other
way round, with the builtin always winning and the `def` uncallable.

**The blocker.** Roadmap item 0026's prototype of packed bytes added six
builtins, and its first names broke three existing programs: `write_bytes`
took the name of a function in 0028's sort, `bytes_of` one in
`tests/unit/kvlog_test.l0`, and `read_all` would have taken one in json's
tests and in editdist. Each program then failed with a type error in its
own code, at a call that had been correct, which is the most confusing
place an error can appear. `roadmap/0031/01-builtin-takes-over.l0` is the
smallest case: a program with its own `flush`, as 0014's wordfreq had before
`flush` became a builtin, reported `an argument of flush must be int, but
this is (list int)`. The prototype had to pick names nobody uses rather
than names that say what the builtin does, and 0032 is about to add the
type for real.

**Why a `def` wins, and not an error at the definition.** An error naming
the builtin would at least appear in the right place, but it would still
break every program that used the name, on every addition. Section 7.1
already answered this for the prelude: a program's function wins over the
prelude's, so the prelude can grow without breaking programs. Builtins are
the same kind of thing, a set of names that grows under programs already
written, and now follow the same rule. What it costs a reader is what the
prelude rule already cost: `(head xs)` means the builtin only if nothing
visible defines `head`. The rule it replaced was chosen because it kept
resolution uniform and the `def` was only a lint concern (below, "Shadowing
a builtin is legal but the builtin always wins"); neither reason survived a
language that gains builtins.

**Why the prelude's own `def` shadows too.** The rule is simply that a
visible `def` wins, so a prelude function named like a builtin shadows it
for the prelude and for programs, and a program's `def` shadows it only for
the program, since the prelude cannot see the program. No prelude function
has a builtin's name today, and none should gain one on purpose; the rule
exists so that a new builtin cannot break a library either.

**What the compiler had to learn.** The checker's and emitter's list of
builtins is now per group, leaving out every name a visible `def` takes.
Three places in the emitter had used the list of all builtins: the
tail-call graph that sets each function's padded arity, the read-only
analysis, and the recognition of section 6.5's nested update, which now
requires `array_set` and `array_get` to be the builtins. Each has a test
that fails when that place goes back to the list of all builtins:
`tests/unit/shadow_test.l0` has a tail call to a wider function named
`neg`, which LLVM refuses to link unless the two arities are joined;
`tests/io/shadow_read_only` updates an array through a function named
`array_len`, which copies if the parameter is judged read-only as the
builtin's would be; and `tests/io/shadow_row` checks the IR of the nested
form with the program's own `array_get`. A wrong read-only judgment costs a
copy, not a miscounted reference, since the emitter adds a reference
whenever it passes on a value it does not own.

**Stage 0 keeps the old rule**, since it is frozen. No function in
`compiler/`, `lib/`, or `tests/lang` has a builtin's name, so the rule
changes nothing stage 0 runs, and the tests of the new rule are all in the
compiled suite or in the compiler's own stage tests.

---

## A row of an array of rows updates in place, written the natural way

**`(array_set g y (array_set (array_get g y) x v))`, with `g` one variable
and `y` the same variable or literal both times, now updates the row in
place** (section 6.5). It means what it always meant, and errors come in
the same order, but the row is never given the second holder that made
every such update copy the whole row. No syntax, builtin, or rule of the
checker changed.

**The blocker.** Roadmap item 0028's maze, keeping its grid as an array of
rows and updating a cell in exactly this form, copied 2.1 million rows and
ran 7.7 times slower than flat (`0028/grids/maze/`), and
`0028/grids/limits/01-nested-update-copies.l0` made 4,000,000 copies in
0.65 s where the placeholder swap made none in 0.10 s. The algorithms
worker's 5,000 by 5,000 table took 11.3 s this way against 0.06 s flat.

Now the maze's array-of-rows version, unchanged, finds the same path on a
2001 by 2001 maze in 0.26 s instead of 1.13 s, with no copies, faster than
the placeholder swap (0.36 s) and within twice the flat version (0.14 s).
The limit program's four million nested updates take 0.02 s instead of 0.65
s. `tests/io/array_rows` sets a million cells this way and checks nothing
copied; `tests/io/array_row_order` checks the error order.

**Why this, and not a builtin.** The shapes weighed were a two-level
builtin `array_set2`, one that returned the old element, and the compiler
recognizing the form. A builtin returning the old element would need a
second result, and there is no pair type. `array_set2` would work, but it is
vocabulary every agent must learn to reach for, and both workers wrote this
nested form first, before any workaround. Recognizing it makes the code
agents already write fast, as read-only parameters did, and costs nothing
in the language: it is a guarantee about when references move, stated in
6.5 so a program can rely on it.

**Why only this form.** It is the one form in which the row obviously has
no other use: the row read and the row written are the same element of the
same array, and nothing else sees the old row. With `y` any expression,
evaluating it once instead of twice could change what the program does, and
with the row bound by a `let` first, the binding is a holder, which the
compiler would have to prove unused elsewhere. The skill says to write it
nested.

**Why the check comes first.** Written out, `(array_get g y)` runs before
`x` and `v` are evaluated, so if `y` is out of range and `v` divides by
zero, the index error is the one reported (section 8). The compiled form
checks `y` with the same runtime call before evaluating `x` and `v`, and
only then replaces the row.

---

## Read-only parameters

**A parameter that nothing of escapes its function is now passed without a
reference** (section 10.3), and so are the fields a `match` on it takes
out, where they escape nothing either. The caller does not add one for a
variable it still uses, and releases anything else it passed once the call
returns; the function neither takes nor releases one. Which parameters are
read-only the compiler works out for the whole program. Nothing in the
source changes, no program is rejected, and no output can differ.

**The blocker.** Roadmap item 0028's sudoku solver called a three-line
candidate check, taking three arrays, nine times per cell per search node,
and every call cost an increment in the caller and a release in the callee:
writing the check inline took the 99-puzzle run from 0.29 s to 0.16 s.
`0028/grids/limits/02-read-only-helper-refcounts.l0` isolates it: 50 million
lookups through a helper taking the arrays took 0.27 s, taking the three ints
0.09 s, and inline 0.07 s. The release is a runtime call that may free, so
LLVM cannot pair it away even when it inlines the helper. The cost pushed
agents toward inlining by hand, the opposite of code worth reading.

Now, on the same inputs: the helper takes 0.10 s instead of 0.26 s, level
with passing ints, and sudoku 0.15 s instead of 0.29 s, as fast as the
hand-inlined version, with identical output and still no array copied. The
compiler on its own source runs in the same 106 ms, its output slightly
smaller.

**What "only reads" had to mean.** The first version counted any `match`
on a parameter, and any `head`, `tail`, or `array_get` of it, as a read.
Sudoku then copied every array on every update, 1.8 million copies where
there had been none: its `put` takes its state parameter apart and updates
the arrays inside, and with the state read-only, the caller's reference
kept the state block holding each array while it was updated. A parameter
is read-only only if no part of it escapes: a read that yields a list,
data, or array counts only if what it yields escapes nothing either. That
also keeps a list walked through `tail` freed as it goes, which a
read-only parameter would have held until the call returned.
`tests/io/array_state` fails, with 400,000 copies, if that rule is
loosened again.

**Why fields of a read-only parameter are read-only too.** Sudoku's
`allowed` matches its state and passes three arrays to the candidate check;
with only the state read-only, each call still took and released a
reference per field. The parameter outlives the whole call, so a field that
escapes nothing needs no reference of its own, and a tail call may pass it
on as it passes the parameter itself.

**Why the lookups became a tree.** Every call now asks for its callee's
flags as well as its padding, and both were a scan of a list of every
function, with the analysis asking again at every call in every pass. That
tripled the compiler's list walking and made it 70% slower on itself. The
table is now a tree walked by the bits of a hash of the symbol, which paid
for the analysis and left the compiler as fast as before.

**Why not called borrowing.** It is what Lean 4 calls borrowed parameters,
inferred the same way, but nothing here resembles Rust's borrowing: nothing
is written, nothing is checked, nothing is rejected, and it changes only when
reference counts move. It is the last-use rule of "A value is released at its
last use" carried across a call.

**Why tail calls decide it.** Section 8 guarantees that a tail call uses no
stack, which means nothing may follow it. A read-only parameter given
something the caller owns, a temporary or a binding at its last use, needs
releasing after the call, so it cannot receive one in a tail call. So a
parameter is read-only only if every tail call to its function passes, in
its position, a read-only parameter or field of the caller; a loop that
threads an array through tail calls qualifies. Disabling that rule breaks
the bootstrap at once: LLVM rejects the prelude's own tail calls, followed
by a release.
The compiler starts from every pointer-typed parameter and removes the ones
that are consumed, or given something owned by a tail call, until nothing
changes. `main`'s parameter is never read-only, since the runtime's entry
point calls it and would have to release it after.

---

## What updates an array in place, said correctly, and no language change for it

**Section 6.5 said an array in a data value copies on every update, and it
does not.** When the value is taken apart by a `match` at its last use, the
match releases the value once it has the fields, so the field's binding is
the array's only holder and the update is in place. That is what the release
rule of 10.3 always did; "Arrays" described it wrongly, and the shipped skill
repeated it. Section 6.5 now lists each case, and adds two that bit
roadmap item 0028's workers and were written nowhere: a read of an array
nested in a later operand, after an `array_set` of it in an earlier one,
copies every time; and `(array_new n x)` of an array makes every element
the same array. It also says what `array_new` costs.

**The evidence.** Three workers wrote nine programs with arrays. Two built
their data structures around arrays in data values (union-find's parent and
rank, dijkstra's graph, wordfreq's table) and measured no copies, against
what the skill told them; `0028/grids/probes/probe.l0` shows the rule case by
case. The read-after-update trap made dijkstra's heap copy on every pop,
passing every test at a tenth of its speed until `L0_ARRAY_STATS` showed it
(`0028/algorithms/limits/03-read-after-set.l0`). It cannot be fixed by
moving the read earlier, since `array_get` can fail and section 8 fixes
which error is reported first, so it is stated instead, and the skill shows
the `let` that avoids it.

**Also:** the parser's type messages name `(array T)`, and a bare `array` in
type position is told it needs an element type, as a bare `list` is. The
shipped skill says what holding input of unknown length as an array costs,
that nested pushes run innermost first, and to use one flat array for a
grid. The repository's skills no longer point at `build/l0i run`, which
cannot run the I/O builtins or arrays. `L0_ARRAY_STATS`'s third line is
documented, and a missing period in 10.3 is restored.

---

## Programs and the runtime are optimized together, and no language change for it

**Every link now passes `-flto`, and the runtime is built as LLVM bitcode,**
so a program and the runtime are optimized as one: `head`, `tail`,
`is_empty`, and the reference counting are inlined into the program rather
than called. **The compiler also builds its table of builtin names once per
context** instead of re-splitting it at every call site. Together they take
the compiler on its own source from 181 ms to 93 ms, with byte-identical
output, and a program heavy in list work, such as Myers' sweep over an array,
from 0.17 s to 0.08 s. No rule in `spec/L0.md` changed: how the runtime is
linked is the host toolchain's business.

**How it was found.** Roadmap item 0027 set out to use arrays in the
compiler. An instrumented build of the compiler (`-fprofile-generate`)
suggested the compiled L0 was the cost: a third of its blocks reversing lists
under `append`, a quarter comparing names, and 16% re-splitting builtin word
tables, since `is_builtin` split seven tables on every call. Building those
tables once removed 23% of the L0's blocks and changed the time not at all.
With the runtime instrumented too, the L0 was 16 million of 334 million
blocks: the rest was the runtime, 22 million increments, 9 million
allocations, and 55 million calls to `head`, `tail`, and `is_empty`, each a
call into a separately compiled object that nothing could inline. Linking
with `-flto` halved the time, and under it the table change is worth a
quarter.

**What it costs.** Builds are slower, since the whole program is optimized
again at link time: a small program from 161 ms to 215 ms, the compiler
itself from 0.5 s to 2.1 s. The compiled suite, which builds every test,
took the same 105 s as before, faster runs paying for slower builds. The
user chose this over applying it to the compiler alone.

**Why arrays were not used after all.** The stage-0 interpreter runs the
compiler's own source for `tools/l0check` and for the interpreted half of
`tests/compiler`, and it is frozen without arrays, as it is without I/O. Using
arrays in `compiler/*.l0` or `lib/prelude.l0` would have meant giving up that
independent run, and the profile showed the largest costs needed no arrays.

**What else changed.** The installed runtime is `lib/l0/l0rt.o`, a bitcode
object, rather than `libl0rt.a`, since indexing bitcode in an archive needs
an `ar` that understands it, which not every host has. `tests/io/tail_calls`
and `prelude_depth`, which build at `-O0` to show that no optimization is
needed for their guarantees, compile `runtime/l0rt.ll` directly, so that no
link-time optimization comes in with a bitcode runtime.

---

## Arrays

**L0 gains `(array T)`,** a second parametric type, and four builtins:
`array_new`, `array_len`, `array_get`, and `array_set` (sections 3 and 6.5).
`array_set` returns an array equal to its argument but for one element, and
updates in place when nothing else holds the array, which the release rule
of "A value is released at its last use" decides. `array` is a reserved
word, and section 8 has two more runtime errors, an index out of range and a
negative length.

**The blocker.** All three of roadmap item 0014's workers needed an indexed
table and had none, and it cost them more than anything else they hit. The
checker's answer to the programs they wanted was `expected list after ( in a
type` and `unknown function array_new`. Their workarounds, measured again
here against the array versions from roadmap item 0021, which are now
`tests/io/array_histogram`, `array_myers`, and `array_paths`, each checking
its answers against an independent computation and that no update copied:

| | list, tree, or trie | array |
|---|---|---|
| histogram of 1 MB | 0.97 s list, 0.17 s tree | 0.02 s |
| Myers' sweep at D = 10,000 | 0.76 s | 0.16 s |
| Dijkstra per query, 10,000 nodes and 100,000 edges | 22.9 ms | 9.2 ms |

CPython takes 10.7 ms per query on the same graph. The workarounds already
gained from the last-use rule; before it they took 1.26 s, 1.37 s, and 31.3
ms.

**Why a parametric type, which costs a listed property.** The l0-bootstrap
skill lists "`list` is the only parametric type constructor, so no
unification is needed anywhere". Every hypothetical wanted arrays of lists
and of data as well as of ints, `(array (list int))` for Myers' lines and
`(array (list Edge))` for Dijkstra's adjacency, so an int-only array would
have sent those programs back to tries. What the property bought survives:
an array's element type is determined by an argument exactly as a list's
is, `array_new`'s element for a new array and the array itself for every
other builtin, so the checker still unifies nothing.

**Why values, updated in place.** Every worker's hypothetical asked for the
same thing: `array_set` returns a new array, so nothing is mutated as far as
a program can tell, and the runtime stores in place when the array's count
is 1, since then nothing could see the old value. That keeps the heap free
of cycles, which is what lets reference counting free everything without a
collector, and it keeps every existing rule about values true. The count is
1 in a loop only under the last-use rule, which is why that came first; with
arrays but the old rule, 0021 measured Myers' diff at 77 s, every update a
copy.

**What an update inside a structure costs.** An array held in another array
or in a data value is copied when updated, since `array_get` and `match`
give it a holder while the outer value keeps its own. Section 6.5 says so,
and roadmap item 0025 holds the question of a builtin that takes an element
out, which would need to return two values and so has no type to return
them in yet.

**The layout.** The header's size field has 8 bits, so an array cannot use
it; size 0, which no other block has, marks an array instead, with its
length in word 0. Arrays come from `malloc` and go back to `free`, since the
free lists stop at 256 words. `L0_ARRAY_STATS` reports how many updates
copied, as `L0_RC_CHECK` reports what leaked, so a test can hold a loop to
copying nothing.

**Why `array` is reserved.** `list` is, and an agent reading a type should
not have to wonder whether `array` might be a variable. No program in the
repository used the name.

---

## A value is released at its last use

**A binding's reference now lasts until its last use on each path, not until
its scope ends** (section 10.3). The last use hands the reference over
instead of adding one; a binding a path stops needing without using it is
released where that happens; a borrowing builtin or a `match` reads a
variable still used later without any reference; and a call takes its
variable operands after its other operands. Section 10.3 states all of it as
guarantees, and section 8 points there. No syntax changed and no program's
output can differ.

**The blocker.** Roadmap item 0021's prototype of arrays found that under the
old rule an array threaded through a loop always had a count of 2 when it was
updated, the loop's binding holding one reference and the update's operand
the other, so an update that could have been in place copied the whole
array: Myers' diff at D = 10,000 took 77 s with arrays against 1.37 s with
lists. Under this rule it takes 0.156 s and copies nothing. Arrays are 0024;
this goes first because they are not worth having without it.

It also pays for itself now. On the compiler's own source, the previous
compiler takes 0.29 s and 28.6 MB and this one 0.15 s and 21.3 MB. The IR it
emits for itself is 15% smaller, 919,626 bytes against 781,034, with 1,157
increments instead of 3,402 and 1,238 releases instead of 3,751; its 364 tail
calls are unchanged. Nothing is reported live under `L0_RC_CHECK`.

**Why this is not 0013 again.** 0013 built the cheapest version, a variable
used once and outside any branch, and measured nothing, since its target was
the input list a whole-input `main` is given, which no release rule can
shrink. This rule reaches through `if` and `match`, and borrows without a
reference, and its target is a count of exactly 1 at the moment of an update,
which the old rule could never give.

**Why the operand order is part of it.** In `(array_set a i (add (array_get
a i) 1))`, left to right would make `array_get`'s the last use of `a`, and
`array_set` would copy. Taking variables after the other operands is
unobservable, since reading a variable can neither do I/O nor fail, which
section 8 already allowed an implementation to move; but whether a loop
runs in constant or linear time per update cannot be left to a freedom, so
section 10.3 now requires it, as section 8 requires tail calls.

**How the compiler knows a use is the last.** The emitter carries the set of
names used after the expression it is emitting, on its path, and a use not in
it is the last. A `let` or an arm removes its own names from that set inside
its body, which is what keeps shadowing right. Free variables are recomputed
where they are needed rather than stored in the tree, which costs about 3% of
the compiler's time and is repaid many times by the compiler's own code
being compiled under the rule. `release_all`, which released every binding
before a tail call, is gone: in tail position nothing is used afterwards, so
everything has already been handed over or released.

---

## Handles that read from and write to memory

**L0 gains `open_bytes`, `open_buffer`, and `buffer_bytes`** (section 6.3).
`(open_bytes s)` is a handle that reads the bytes of a list and then ends;
`(open_buffer)` is a handle that keeps what is written to it, and
`(buffer_bytes h)` returns that as a list. Code that reads and writes handles
cannot tell them from files.

**The blocker.** Two of roadmap item 0014's workers hit the same wall from
opposite ends. csvcol's parser had to read a file in the program and a string
in its tests, and L0 has no function values, so a parser cannot take its
byte source as an argument (`error: from_stdin is a function, and L0 has no
function values`). The worker turned it inside out into a pure (state,
byte) step function that each source drives, which allocated a state per
byte and ran 4 times slower than the direct parser, 1.07 s against 0.27 s on
14.5 MB. wordfreq wrote its tokenizer twice. base64 and minigrep kept their
direct code and paid for it in their tests instead: 68 lines of temporary-file
plumbing, fixed names in `/tmp`, and two opens and a close per input.
`tests/unit/csvcol_test.l0` now tests the direct parser on strings, with
csvcol's own test cases. On the same 14.5 MB file, column 5, the direct
parser takes 0.34 s and the step function 1.00 s on this machine, Python's
`csv` module 0.18 s, and both L0 versions print exactly what Python does. On the same 14.5 MB file, column 5, the direct
parser takes 0.34 s and the step function 1.00 s on this machine, Python's
`csv` module 0.18 s, and both L0 versions print exactly what Python does.

**Why handles, and not function values.** Both workers proposed these
handles. The one who also sketched function values noted that they would not
cover this case alone: a string source must keep its position somewhere, and
a function without a closure has nowhere to keep it. Function values would
also end one of the properties that keep the checker simple, that name
resolution is purely syntactic. Handles need no new type or syntax, and the
code under test is exactly the code the program runs, which a second copy
over lists would not be.

**What the handles cost.** `open_bytes` keeps a reference to the list it is
given rather than copying it, so opening costs nothing whatever the length,
and the runtime releases it at `close` or when the program ends, as if the
handle were closed then. A buffer keeps one byte per byte in a buffer that
grows, and builds cons cells only when `buffer_bytes` asks, so collecting a
large output does not cost 24 bytes per byte until it is read. Neither can
fail once open, so `flush` and `close` of a buffer return 0, and a read never
waits, so reading one never delivers output held back for standard output.

`buffer_bytes` of something that is not an open buffer is the empty list,
since a list result has no room for a negative code; the only way to get
that wrong is to pass it the wrong handle, which a test of the code would
show at once. `lib/io.l0` wraps the three in `open_in_bytes`,
`open_out_buffer`, and `buffer_contents`, with `IoOpened` as the other
openers have, since opening can fail when every handle is taken.

---

## Appending to a file, and replacing one in a single step

**L0 gains `open_append` and `rename`** (section 6.3). `open_append` opens a
file for writing at its end, creating it if it is missing; `rename` gives a
file another name, replacing whatever had it, in one step. **Opening a
directory for reading now fails with -5,** where it used to succeed and fail
on the first read.

**The blocker.** Roadmap item 0014's kvstore could only add a line to its
store by reading the whole file and writing it back, since `open_write`
empties a file and nothing appended: 20 ms at 10,000 lines and 235 ms at
200,000, against 12 ms for `echo >>` at every size. Worse, because
`open_write` empties the file before anything is written and nothing could
replace a file whole, a crash while saving lost the store, so crash safety
could not be written at all. The checker said `unknown function
open_append` for the program the worker wanted. `tests/unit/kvlog_test.l0`
is now that program, an append-only store that compacts by writing a new
file and renaming it over the old one. Adding one line with `open_appending`
now takes 7 ms at 10,000 lines and at 200,000, where reading and rewriting
takes 25 ms and 266 ms on the same machine, and `sh -c 'echo >>'` 11 ms.

**Why these two, and not seek or remove.** They are exactly what the
append-only store needs: appending makes a write cost the record rather than
the store, and renaming makes compaction safe. The worker's hypothetical
also listed `remove`, which its bucket workaround wanted for cleaning up;
the log needs no cleanup, so it waits for a program that does. Seeking
belongs with the arrays goal, 0021, where in-place update is the question.

**Why rename says so little about why it failed.** `errno` is out of reach
of the runtime, as "Files, arguments, and names reserved for the standard
library" records, so the reason comes from `access()`. A missing source can
be told apart that way, which is -3. Permission to rename depends on the
directories and not the file, which `access()` on the paths cannot judge
reliably, so everything else is -5.

**What "one step" promises.** Another program, or this one after it stops
for any reason, sees the old file or the new one under `to`. That is POSIX's
`rename`. It does not promise that the new file's bytes survive the machine
losing power, which would need the operating system told to write them to
the disk before the rename. That is a separate facility, with a real cost,
and waits for a program that needs it.

**Why appending goes through `fopen`.** The runtime is one text for every
host, and `O_APPEND` and `O_CREAT` have different values on macOS and Linux,
so `open` cannot be given them. `fopen` with mode `"a"` opens for append on
both, so the runtime takes a duplicate of its descriptor and closes the
`FILE`, never looking inside it. A missing file is created first with
`creat`, as `open_write` creates one, so both create files with the same
permissions. The descriptor is in append mode, so each delivery lands at the
end of the file as it is then, even with another writer.

**Why a directory now fails to open.** It used to open, on macOS and Linux
alike, and fail on its first read. `read_line` and `file_read_line` treat a
failed read as the end of input, so a directory read as an empty file,
which is the silent failure the library otherwise avoids; and a failed open
is where every program already handles a path it cannot read. The runtime
asks `opendir`, which returns an opaque pointer, so no structure whose
layout differs between hosts is involved.

**Compiling them.** `rename` is the first builtin with two paths. Both are
borrowed, as a path always was, so the compiler now releases every argument
of a path builtin rather than the first. Neither name was defined by any
program in the repository.

---

## A program can learn that its writes failed

**L0 gains `flush`,** a builtin that delivers what a handle holds back,
leaves it open, and returns 0, or -5 if any byte written to it was lost, or
-2 if it is not open for writing (section 6.3). It works on standard output
and standard error, which `close` refuses. **A write failure no program was
told of is now a runtime error at exit,** status 70 whatever `main` returned,
where before it was silently ignored.

**The blocker.** Roadmap item 0014's base64, run with standard output closed,
wrote nothing, and exited 0: every `write_byte` returned 0 because it only
buffers, and `(close 1)` returned -2. `write_to` and `write_byte` only buffer,
`close` was the only thing that reported a write failure, and it refuses
handles 0 to 2, so no L0 program could find out. The system `base64` in the
same situation says "write error" and exits 1. `tests/io/write_failure` is
now that program's check, and it passes on macOS and Linux.

**Why a builtin, and not a result from `write_to`.** When a write fails
depends on how much the runtime holds back, which section 6.2 leaves to the
implementation, so a `write_to` that returned -5 would return it at a moment
the program cannot predict and another implementation would not reproduce.
`flush` makes the moment of the check the program's own. It is also what
`close` already did for a file, less the closing, which standard output
cannot afford: a filter checks once at the end and can still write to it.
The name is the one every other language uses. Like any new builtin it
takes the name from programs, since a builtin wins in call position; 0014's
wordfreq defined a `flush` of its own, which now has to be renamed.

**Why a failure sticks.** A lost byte stays lost, whatever succeeds after it,
so once a write to a handle fails every later `flush` and `close` of it
return -5. Otherwise a program would have to flush after every byte to know
that its output was whole. The runtime already kept this state per handle;
it only had no way to say so for handles 0 to 2.

**Why the host reports what the program never saw.** A `main` that takes its
input has its result written after it returns, so it could never check that
write, and the compiler is such a program: with standard output on a full
disk it would have left truncated IR and exited 0. Leaving the exit status
alone would have kept exactly the failure this entry is about for every
program that does not flush. So a failure is *reported* once a `flush` or
`close` of its handle returns -5, and one still unreported when the program
ends, including one the final delivery causes, is the runtime error of
section 8. It overrides any status, since the status was computed without
knowing, and a program that was told keeps the status it chose, so base64
can still exit 1 with its own message. Status 70 and the `l0: runtime error:`
line are what the runtime errors already use; the message is `write failed`,
and if standard error is what failed, the status alone says so.

Section 6.3 said nothing about what happens when delivering held-back bytes
at exit fails; it now does, and sections 6.2, 8, 9, and 10.3 say the same.

**The seed.** `@l0_flush` is appended to the runtime interface, and the
exit-time check is in the runtime alone, so programs built by an older seed
get it too. Stage 0 is frozen and does not know `flush`, so the tests are in
`tests/io`, with hand-written expectations; its own exit status on a lost
write is unchanged, which no test compares.

---

## The standard library documents itself

**What an agent reads about L0 now comes from the toolchain, not from
copies.** `l0 init` used to copy the specification, the examples, and the
library into each project, where they stayed as the toolchain moved on. Now
it copies only `AGENTS.md` and the `l0-code` skill, and `l0 spec`, `l0
examples`, and `l0 doc` show the installed ones.

**`l0 doc` reads the library's own comments.** A `;;` block directly above a
`def` or `data` is its documentation and makes it public; one without is
internal. `l0 doc` lists every public name with its signature and the first
sentence of its comment, and shows one file, one name, or a search in full.

**Why not skills, or the spec.** A skill describing the library is copied by
`l0 init` too, so it drifts just as the library copies did, and it is a
second record of every fact that nothing checks against the first. Library
details in `spec/L0.md` would make the language's definition grow with every
helper. Documentation next to the code is reviewed with the code, and a test
pins the index, so a change to the library's surface cannot go unnoticed.

This is not a language change. `;;` is an ordinary comment to the compiler.

---

## Reading a line can report a failure, and no language change for it

**`lib/io.l0` gains `next_line` and `file_next_line`,** which return an
`IoLine`: `(IoLine s)`, `(IoEnd)`, or `(IoError code)`. All three of roadmap
item 0014's workers found that `read_line` and `file_read_line` treat a
failed read as end of input, so a failed read looked like a short file,
which the skill tells a program never to allow. linediff, minigrep, and
kvstore each wrote their own reader. Two of their hypotheticals proposed this
same type, one with a code and one with words; it carries the code, because
kvstore had to match on the text of `IoFailed`'s words to tell a missing
file from others, and `io_error` still gives the words.

`read_line` and `file_read_line` stay as they were, since most programs
reading standard input only want the lines, and now say in their comments
that a failure ends a line.

**The prelude's `length` and `append` no longer take a stack frame per
element,** nor does `lib/io.l0`'s `args`. `length` of 10 million elements
used 320 MB of stack. `append` now reverses its first list and reverses that
onto the second: twice the copying, for no measured change in the compiler's
time, since it only ever appends short strings.

None of this is a language change: no rule in `spec/L0.md` changed, and the
prelude remains ordinary L0. It is recorded here because the prelude is what
every program links, and because the choice between an `IoLine` type and a
second return value is one a later reader would otherwise have to guess.

---

## A tail call uses no stack

**Every tail call is now guaranteed** (section 8). Section 8 defines tail
position and tail calls, and a chain of tail calls of any length, between
functions of any arities, runs in the stack of one activation. Before, it
left the outcome unspecified, and the outcome depended on the host: the
optimization level, whether LLVM inlined the functions involved, and how
many arguments the target passes in registers. That was the question roadmap
item 0011 researched; its measurements are in `roadmap/0011/`.

**The blocker.** L0 has no loops, so every loop is recursion, and a state
machine written as mutually recursive functions is ordinary L0. Measured
with an 8 MB stack before this change:

```
self-recursive loop, -O0                        exhausted at 1 million
tail calls between a 10- and a 2-argument
  function, -O2, neither inlined                exhausted at 1 million
```

The second is the default build of a program large enough that LLVM does
not inline its loops, and a call between functions of seven and two
arguments behaved differently on arm64 and x86-64. So the same program could
run on one machine and exhaust the stack on another. The compiler itself,
built at `-O0`, needed a 128 MB stack to compile itself.

**How.** A tail call is emitted as `musttail call` followed by `ret`, and an
`if` or `match` in tail position returns from each branch instead of joining
(10.3). `musttail` makes LLVM keep the guarantee at every optimization level
or refuse to compile, so a toolchain that cannot honor it fails at build
time, never at run time. It requires caller and callee to have the same
prototype, so a function takes as many parameters as the widest function in
its tail-call component, padded with zeros (10.2). The program's `main` is
wrapped, because the runtime calls every `main` with one argument.

**Why this way.** 0011 compared five implementations by rewriting the IR the
compiler emitted:

- `tailcc`, LLVM's convention for guaranteed tail calls, needs no padding, but
  LLVM rejects it for RISC-V, 32-bit ARM at `-O0`, and wasm. Section 10 makes
  the output the same bytes on every host, so the compiler cannot choose it
  per target.
- `musttail` with the C convention and no padding fails at once: the prelude
  itself tail-calls across arities.
- Padding every function to the module's widest costs 13% more code at `-O0`,
  and one wide function makes every call pay for it. Padding per component
  pads only what needs it.
- Turning self tail calls into loops in the emitter is portable, but covers
  200 of the compiler's 314 tail calls and none that are mutual.

**Measured after**, all on an 8 MB stack unless stated:

```
the eight shapes 0011 tested, 10 million iterations,
  at -O0 and at -O2 with nothing inlined       all complete
the compiler at -O0, compiling itself          on a 1 MB stack, with
                                               L0_RC_CHECK, output identical
the compiler's own IR                          898,092 -> 850,276 bytes
```

The IR is smaller because branches in tail position no longer store to a
slot and join. The compiler emits 336 `musttail` calls in itself, and 29
allocas remain, all for branches that are not in tail position. The compiler
IR assembles at `-O0` and `-O2` for x86-64, AArch64, RISC-V, and 32-bit ARM;
wasm refuses it at build time without the tail-call feature, as intended.
Both suites pass on macOS arm64, and on Linux aarch64 and x86-64 with
clang 18.

**What it costs.** Self-compilation went from 0.21 to 0.26 seconds,
including process start, best of three; not yet profiled. And the property
section 10.2 had, that a function's IR prototype is its L0 parameters and
nothing else, is gone.

**What was decided along the way.**

- *A builtin in tail position is not a tail call.* Builtins cannot recurse,
  and `head`, `tail`, and the others that borrow their argument release it
  after the call, which `musttail` would forbid.
- *No alloca moves to the entry block.* 0011 found that a loop within a
  function would allocate its join slots on every iteration. No emitted
  function has a back edge, so each alloca runs at most once per call, and
  10.4 now says a compiler that emits a loop must hoist them.
- *`main`'s body is `@l0_f_main.body`.* The runtime must keep calling
  `@l0_f_main`, because the seed defines that symbol and links against the
  same runtime. No L0 name can contain a dot, so the new symbol cannot
  collide with a program's function.
- *How deep recursion that is not a tail call may go is not specified,* and
  an implementation may run some of it in constant stack: LLVM already turns
  `(add 1 (count ...))` into a loop at `-O1`.

**Spec text corrected with it.** 10.3 said "a call in tail position stays
one", which was false for the emitted IR at every level, and that a streaming
program runs in constant memory, which held only for the heap. It now names
`L0_STACK_MB` and its 512 MB default.

---

## Memory is reclaimed by reference counting

**Programs now free memory.** The compiler emits reference counting, and the
runtime frees a block when its count reaches zero (section 10.3). Nothing a
program computes or writes changes. What changes is what it holds: a block is
freed no later than the end of the scope that bound the last reference to it.
This is the second of the two changes roadmap item 0010 planned; the first,
"Blocks describe their own layout" below, gave every block the header this
one needs.

**The blocker.** From roadmap item 0006, `0006/limits/02-no-reclamation.l0`: a
loop never holding more than about 1 KB live reached 9.8 GB after 10 million
iterations. Now:

```
   100000 iterations: rss 1.5 MB
  1000000 iterations: rss 1.5 MB
 10000000 iterations: rss 1.5 MB
```

A streaming program that builds a list for every line of its input, the
`tests/io/lines` numberer, holds 1.6 MB at 10 MB of input and 1.6 MB at 100
MB. The compiler compiling itself peaks at 26.3 MB, against 104.8 MB before
this item began on the same source and 179 MB after its first change.

**Why this scheme.** An L0 heap cannot contain a cycle, since there is no
mutation, evaluation is strict, and `let` cannot define a recursive value, so
counting reclaims everything with no collector. The emitter needs no analysis
of later uses: a use of a variable adds a reference, and the variable's own is
released when its scope ends. The one subtlety is tail position. `if` and
`match` join through a stack slot, so releasing at the end of a function would
put a release after every recursive call, and the loops LLVM now turns into
jumps would recurse instead and exhaust the stack. So in tail position every
binding in scope is released after the final call's arguments are evaluated
and before the call. That is also what frees a list as a loop walks it.

**What it costs.** Speed: every change to a count is a call into the runtime,
and the compiler compiling itself goes from about 0.04 to 0.15 seconds. Speed
alone does not justify a change here, but it is on record. And precision:
releasing at the end of a scope rather than at a value's last use means a
`main` that takes its input holds all of it while it runs. 0006's line filter,
written that way, still holds 2.7 GB at 100 MB of input, half of what it did.
Its `main` passes `input` to a call that is not in tail position, so `main`'s
parameter keeps the head of the list, and with it the whole list, alive.
Releasing at last use would fix it. That is recorded as its own roadmap item
rather than folded into this one, since streaming programs, which the l0-code
skill now recommends for large inputs, do not need it.

*Corrected later, the same day: that diagnosis was wrong.* A `main` that takes
its input and ignores it peaks at the same 2,504 MB at 100 MB of input as the
line filter does. The cost is the input list the runtime builds in full before
`main` starts, one 24-byte cons cell per input byte, and no rule for when to
release can reduce it; only the streaming form avoids it. A release-at-last-use
rule was built anyway, for variables used once outside any branch, and changed
nothing measurable: the line filter at 2.5 GB, the compiler at 26 MB and 0.15
s. It was reverted and roadmap item 0013 dropped. The paragraph above is left
as written, since it is the reasoning that opened 0013.

**How it was verified.** `L0_RC_CHECK` makes the runtime poison freed blocks
and never reuse them, so a use after free is a runtime error, and report any
counted block still live at a normal exit. The check was shown to fire, on a
program built by the previous compiler, which never releases. `tools/test.sh
--compiled` now runs every compiled program under it, the compiler included:
the bootstrap reached a byte-identical fixpoint on the first try, and the
compiler compiling itself under the check leaves nothing live and writes the
same bytes.

---

## Blocks describe their own layout, as the first step to reclaiming memory

**No change to what a program does.** Every block now has a header word in
front of it, holding a reference count, its size, and a mask of which of its
words are pointers (section 10.1); allocation goes through two new runtime
calls that take the mask (section 10.3); and a constructor may have at most
31 fields, a new compile error (section 4). Nothing is freed yet. This is the
first of the two changes roadmap item 0010 planned for reference counting,
and the reasoning for the whole design is recorded there.

**Why the mask comes from the compiler.** Freeing a block means releasing the
blocks it points to, so the runtime must know which words are pointers. For a
data block that follows from the constructor's field types. For a cons cell
it does not: whether the head is a pointer depends on the list's element
type, which only the checker knew, and at run time every value is one `i64`.
So the emitter now carries each expression's type as it emits it, computed
bottom-up exactly as the checker computes it, and passes the mask to
`l0_new_cons(head, tail, mask)` and `l0_new_data(tag, nfields, mask)`. That
refactor of the emitter is most of this change's risk, which is why it lands
before any counting: behavior is unchanged, so the whole differential suite
checks it against stage 0.

**Why 31 fields.** The mask is 32 bits of a one-word header and word 0 is the
tag. The widest constructor in the repository has 5 fields. One word keeps a
cons cell at 24 bytes rather than 32.

**Why the old calls stay.** The runtime interface is append-only, because the
seed declares its functions by name. `l0_cons` and `l0_data_new` remain, and
make blocks whose count is at its maximum, which means never freed. A program
an older seed compiled therefore keeps working unchanged once freeing exists.

**What it costs, measured.** One word per block: a cons cell grows from 16
bytes to 24, and the arena now rounds to 8 bytes rather than 16. The compiler
compiling itself, on the same 107 KB of source, goes from 104.8 MB resident
to 179 MB, which is more than the header alone. The rest is the emitter's own
new garbage, each value carrying its type and the call-type tables built per
call, and a 16% longer output, since every cons call now passes its mask.
Nothing is freed yet, so all of it accumulates. That is accepted as temporary:
the next change is what reclaims it, and roadmap item 0010's target, the
compiler below its old peak, is measured after that change and not this one.

---

## A test framework, and no language change for it

**No change to the language.** `lib/test.l0` and `l0 test` are a library and a
tool, built entirely on the I/O of the two entries below. This entry records
why they are shaped as they are, since the shape is what agents will copy.

**The blocker.** L0 had only a convention for tests, a `check` function
consing `y name` or `n name` onto `main`'s result. It never said what was
computed or expected; it put every assertion in one nest inside `main`, and
that nest is exactly where closing parentheses get miscounted, three times in
the session that built the two entries below; one runtime error ended the
whole run; and nothing gave an exit status or ran a subset.

**The shape, chosen with the user:**

- **Tests are found, not listed.** L0 has no function values, so a program
  cannot enumerate its own functions. The driver can, from the source: any
  `(def test_NAME () int ...)` is a test, and `l0 test` generates a `main`
  that runs the one named by `(arg 0)`. With nothing to register, the easy
  thing is many small tests, which is what keeps the parentheses short.
- **Each test is its own process.** The program is built once and run per
  test, so a runtime error fails one test, reported with its message. That
  also makes failure testable, which nothing in L0 can do otherwise, since
  runtime errors cannot be caught: `expect_NAME` names the error `test_NAME`
  must die with.
- **Assertions say what went wrong.** Each shows got and want, strings as L0
  literals that paste back into a test, with the first differing byte. Each
  writes as it runs and returns 1 on failure, so a test returns the sum, and
  `add`'s left-to-right order keeps the report in source order.
- **TAP**, because agents and CI already parse it, with a nonzero exit on any
  failure.
- **Golden files, filtering, and seeded random inputs** for large outputs,
  focused runs, and property tests. `--bless` lists every golden file it
  wrote, since blessing makes whatever the code does now correct.

**What it cannot serve.** Stage 0 cannot run I/O, so the oracle-checked suites
(`tests/lang`, the compiler's stage tests) stay on the old convention; the
framework is for `tests/io`, the standard library, program-writing workers,
and projects made by `l0 init`, which now ships `l0/test.l0` and a worked
`l0/examples_test.l0`. `tests/io/framework.sh` checks `l0 test`'s whole
report on a fixture against hand-written expectations, and runs the shipped
example tests, which must pass.

The repository's own tests of what stage 0 cannot run moved to it where they
could. `tests/unit/io_test.l0` has sixteen tests of `lib/io.l0` and the
builtins beneath it, taking over what the old `handles` program printed, and
`tests/unit/order_test.l0` checks evaluation order through a file instead of
standard output. `tools/test.sh --compiled` runs each through `l0 test` in a
scratch directory, and points it at the compiler it just built with the new
`L0_COMPILER` and `L0_RUNTIME` overrides, since `l0 test` otherwise uses the
seed's. What stays in `tests/io` is what a test function cannot check: the
two forms of `main`, exit status, standard input, arguments, and timing.

---

## Files, arguments, and names reserved for the standard library

**L0 can open files and read its command-line arguments.** Seven builtins,
over integer handles into a runtime table: `read_from`, `write_to`,
`open_read`, `open_write`, and `close` (section 6.3), and `arg_count` and `arg`
(section 6.4). Handles 0, 1, and 2 are the standard streams, so `read_byte` is
exactly `(read_from 0)`. Upper names beginning with `Io` and an uppercase
letter are now reserved for the prelude (section 7.1), which a program that
declared one will now fail to compile over.

**The blocker.** Roadmap item 0006 could not write a file copy: there were no
arguments, no files, and no way to fail but a crash. The checker confirmed
the missing pieces (`unknown function 'read_file'`, `unknown function
'write_file'`, `unknown function 'fail'`). `tests/io/filecopy` is now the
program 0006 said should have been possible. `filecopy.sh` checks a
byte-exact copy of 300 KB of random data, an existing destination emptied
first, and the exact message and status for a missing source, an unwritable
destination, an unreadable source, and a usage error.

**Why failure is a data type, and where the type lives.** "The route to memory
management and I/O" chose safe facilities partly because an operation that
can fail can return a data type with a failure case, and exhaustive `match`
then rejects a program that forgets it. So `lib/io.l0` declares `IoFile` and
`IoOpened`, with cases `IoOpened` and `IoFailed`, and wraps the builtins in
`open_in`, `open_out`, and friends. A program that matches on `(open_in path)`
and leaves out `IoFailed` does not type check.

The builtins themselves return negative codes rather than data types, because
a builtin's result type would have to be predeclared.

**Why reserve names.** Type and constructor names are one namespace across
the prelude and the program (section 7.1), for reasons that section records.
So any type the library declares breaks every program that already declared
the same name, and each later library type would do it again. Three answers
were weighed with the user: reserve a prefix for the library; group type and
constructor names per group, as functions are, which would touch about 44
resolution sites and override 7.1's stated reasons; or accept collisions.
Reserving was chosen. It is one checker rule, it can never break a program
again once made, and a reader can see which types are the library's. The
prefix is `Io` for what exists now; a later library area that needs types
gets a prefix of its own, which will itself be a breaking change for any
program that used it, once.

The rule is `Io` followed by an uppercase letter, so `IoFile` is reserved and
`Iota` and `Ion` are not. Only program declarations are checked. For that to
work outside `tools/l0`, `tools/l0c` and `tools/l0check` now put
`lib/prelude.l0` and `lib/io.l0` in the prelude group whenever `lib/io.l0` is
among their files, through a shared `tools/bundle.sh`; otherwise they
compile everything as the program, as before. `examples_check` checks the
examples the same way.

**What the runtime could and could not do portably.** It stays one text for
every host, so:

- files open with `open` and flags 0, since read-only is 0 everywhere, and are
  created with `creat`, since the values of `O_CREAT` and `O_TRUNC` differ
  between macOS and Linux
- `errno` is a macro over a function whose name differs between platforms,
  so the reason an open failed comes from `access()` instead. That is why the
  codes are few: no such file and permission denied can be told apart
  reliably, and everything else is -5
- a write failure can only be reported by `close`, since bytes may be held
  back until then; section 6.3 says so, and the l0-code skill tells programs
  to check it

Every handle is buffered. Standard output and error are flushed before any
read that has to wait, which keeps 6.2's prompt guarantee, and every handle
is flushed when the program ends, including by a runtime error.

**Verified on Linux too.** Both suites pass in an Ubuntu container, 56 and 62.
The permission case first failed there, because Docker's bind mount does not
enforce permission bits; on the container's own filesystem it passes, and
`filecopy.sh` now checks that case only where a mode-000 file really cannot
be read.

---

## Reading and writing as a program runs

**L0 has effects.** Two builtins, `read_byte` and `write_byte` (section 6.2),
and a second form of `main`, `(def main () int ...)`, which reads nothing up
front and returns the exit status (section 9). This is the first change made
under "The route to memory management and I/O" below, and the one that ends
L0's purity. Sections 1, 8, and 10.3 change with it.

**The blocker.** Roadmap item 0006 could not write a program that asks for a
name and then greets it. The nearest L0 program printed its question after its
answer, measured with the answer sent at t+0 and end of input at t+3:

```
  t+ 0.00s  stdin  b'Ada\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'What is your name? Hello, Ada!\n'
```

Now `tests/io/prompt` holds the program 0006 said should have been possible,
and `prompt.sh` sends the answer only once it has read the question back. A
version that reads before it asks fails it after its 5-second watchdog, which
was checked. The same change removes two of 0006's memory costs, the whole
input held before `main` runs and the whole output held until it returns. A
streaming copy of 1, 10, and 100 MB peaks at 1.1 MB each time, where `main`
returning its input peaks at 18, 173, and 1704 MB.

**Why bytes, and not lines or strings.** The builtins are the smallest pair
the rest can be written from, so the runtime interface grows by two functions
and not by a family. `read_line`, `write_str`, and `write_line` are ordinary L0
in a new `lib/io.l0`, which `tools/l0` links beside `lib/prelude.l0` in the
prelude group, so a program may define its own. `read_byte` returns -1 at end
of input rather than a data type with an end case, so it needs no predeclared
type: a predeclared constructor would break every program that already used
its name, since section 7.1 does not group constructors. That problem is still
waiting for 0009, whose file operations can fail.

**Why `lib/io.l0` is not in the prelude.** The stage-0 interpreter runs
`lib/prelude.l0` and the compiler, both for the compiler's stage tests and for
`tools/l0check`, and stage 0 is frozen, so it will never know the new
builtins. The compiler's own source and the prelude therefore must not use
them.

**Why a second form of `main`, and not only the builtins.** The existing form
reads all of standard input before `main` runs, so `read_byte` inside it can
only ever see end of file. A program that streams has to be one the host does
not read for. Its result became the exit status because nothing else is
written on its behalf, and a program that streams needs a way to fail other
than a crash. That is a first installment of 0009's "failure". The runtime
calls every `main` the same way, so one with no parameters still compiles to
`@l0_f_main(i64)` and ignores the argument (section 10.2), and
`@l0_main_ret_kind` gains a kind 3.

The old form keeps working exactly as before, and can use the builtins too:
`read_byte` returns -1 from the start, and bytes written come before the
result.

**What the ordering costs, which section 8 had already priced.** Evaluation
order was specified left to right from v1 "so that even failure is
deterministic", and its paragraph said an effect would find the order already
pinned down. It did. What is lost is the implementation's freedom to reorder
or drop an evaluation that could have an effect, and section 8 now says an
evaluation may be moved or dropped only if it can neither do I/O nor fail. The
compiler never used that freedom. LLVM cannot use it either, since the
builtins are calls into the runtime.

**Output buffering is specified by what it must not hide.** An implementation
may hold output back, but only until a `read_byte` has to wait, or the program
ends, including by a runtime error. That is exactly what makes a prompt
appear, and it lets the runtime buffer 64 KB in each direction. A runtime
error now delivers what was written before it and then the diagnostic, rather
than producing no output at all, since output that had already reached a
terminal could not be taken back.

**Section 10.3's case for the arena is corrected.** It said never freeing was
correct because a program "runs once and exits", and named a program that runs
unbounded as the change that would break it. A program that streams is that
change. The paragraph now says what is true: never freeing is safe, memory is
total allocation, and a streaming program that allocates per line grows
without bound while one that does not stays constant. 0010 is the fix.

**Tests without an oracle.** Stage 0 cannot run any of this, so the new
`tests/io/` suite runs only under `tools/test.sh --compiled`, and its
expectations are written by hand rather than blessed. Checker errors for the
new builtins and the new `main` are in `tests/compiler/check_errors`, which
runs the compiler's checker under stage 0 and so still has both.

---

## Checking a fragment still checks its main

**A check that used to pass now fails.** With `#nomain`, a program `main` that
is present must still have section 9's signature. Section 9.1 says so, and a
wrong `main` is now reported at its declaration, with a file and line, rather
than at no position.

**The blocker.** Roadmap item 0006 wrote this, to show that command-line
arguments cannot be reached:

```
(def main ((args (list (list int))) (input (list int))) (list int)
  (head args))
```

`tools/l0check` printed `ok` for it. Checking passes `#nomain`, and a present
`main` was not examined at all, although 9.1 said `#nomain` "relaxes nothing
else". Only `tools/l0 build` rejected it, with no location:

```
error: main must take one parameter of type (list int)
```

The worker nearly recorded a blocked program as passing, because the one rule
it had been given was to trust `l0check`. A checker that says `ok` about a
program that cannot run is worse than one that says nothing.

**`tools/l0check` now uses the compiler's checker.** It used to run stage 0's,
which is frozen, so it could not have been fixed there. The compiler's checker
runs under the stage-0 interpreter, which executes the current
`compiler/*.l0` and so is never stale, and it takes about a tenth of a second
on a 30 KB file. This also had to happen before the next language item: once
L0 gains builtins stage 0 does not know, stage 0's checker would reject every
program that uses them. Stage 0's checker remains in use as the oracle in
`tools/test.sh`, which is its only job. Diagnostics now carry the compiler's
wording, which differs slightly from stage 0's.

When the compiler's own source starts using a feature stage 0 cannot run,
`l0check` will need a native compiler built from the current source instead.
It falls back to `build/l0c-native` already, but that one is only as current
as the last `tools/test.sh --compiled`.

**One more stale-compiler trap, found verifying this.** In a checkout,
`tools/l0` rebuilt `lib/l0c` from the seed only when it was missing, so after
a seed refresh `l0 check` and `l0 build` went on using the previous compiler,
and reported the old unlocated message. It now rebuilds when the seed or
`runtime/l0rt.ll` is newer than what it built. An installed prefix has no
seed beside it and is unaffected.

---

## The route to memory management and I/O

**No semantic change yet. L0 is exactly the language it was before this
entry.** What this records is a decision about what L0 becomes, made before
any of it is built, because it ends a property the spec has had since v1.

**The decision.** L0 gains memory management and I/O as safe facilities
implemented in the runtime, and I/O becomes effects in expression position,
ordered by section 8's existing left-to-right rule. L0 code does not get raw
memory. This ends L0's purity, deliberately. Section 8's guarantee that a
program which type checks cannot read uninitialized memory stays whole.

**The evidence.** Roadmap item 0002 tried to write the runtime in L0 and
found ten limits, every one of them a systems primitive: loads and stores at
an address, static storage, calls to C, symbol names, C types. Item 0006 then
wrote four ordinary programs, a line filter, a word counter, a prompt, and a
file copy. None of them needed any of those primitives. What they needed was
reclaimed memory, incremental standard input and output, arguments, files,
and a way to fail. The prompt and the file copy cannot be written at all
today, and the two that can are costly, measured:

- the line filter uses 53 bytes of memory per input byte, 16 GB for one pass
  over 300 MB
- the word counter, whose table never holds more than 14 entries, uses 208
  bytes per input byte
- a loop that never holds more than about 1 KB live reaches 9.8 GB after 10
  million iterations

**Why safe facilities rather than primitives.** L0 is written by agents, so
what counts is whether the checker catches their mistakes. An operation that
can fail can return a data type with a failure case, and exhaustive one-level
`match` then rejects a program that forgets the error path. Raw memory gives
the checker nothing: every value is an `i64` at run time, so a wrong pointer,
length, or errno passes. And freeing by hand cannot be made safe in L0 at all,
because lists share their tails invisibly.

**Reclamation will be reference counting.** It is complete for L0 without a
cycle collector: there is no mutation, evaluation is strict, and `let` cannot
define a recursive value (section 5.3), so an L0 heap can never contain a
cycle. It is also invisible to programs, so the whole differential suite
keeps judging it against stage 0.

**What this overrules.** "Output before input is an accepted blocker" below
preferred keeping `main` pure and re-running it on a longer transcript each
turn. That fixes prompting and nothing else: for the word counter it would
mean 2.8 million re-runs on 100 MB of input. Its blocker and measurement
stand; its preferred shape is rejected on this evidence.

**What was deferred, not rejected.** The systems primitives return to the
table if a program needs them, or if writing the runtime in L0 becomes a goal
in its own right. `roadmap/0002/` holds their list and first drafts.

**The order.** Checking enforces `main`'s signature first, a small fix 0006
found. Then streaming standard input and output, then arguments, files, and
failure, then reference counting. Streaming comes before reclamation because
it changes what can be written, not only what it costs, and 0006 measured
that neither bounds memory without the other.

---

## The runtime is LLVM IR, and stack exhaustion is checked rather than caught

**No change to what an L0 program means.** Every program produces the same
output, the same errors, and the same exit status as before. What changed is
what a compiled program is made of. Section 10.3 now says the runtime is LLVM
IR that calls libc, and adds one function to it, `@l0_stack_check`, which
every compiled function calls on entry.

**The blocker.** Every compiled program linked `runtime/l0core.c` and
`runtime/l0rt.c`, and "A new goal" below makes no C source in a compiled
program the first milestone. Roadmap item 0001 set out what the C did and
what each part needed from the operating system. Lists, data blocks, `div`,
`mod`, and error reporting need nothing but an allocator and `write`.
Allocation needs `malloc`, input and output need `read` and `write`, and the
entry point runs the program on a 512 MB thread so that deep recursion works.

**The replacement** is `runtime/l0rt.ll`, hand-written IR that calls 14 libc
functions and nothing else. It exports the same names the C did, so the
checked-in seed, which declares them, links against it unchanged. It carries
no target triple, and it is the same text on every host because it avoids
everything whose shape differs between operating systems:

- file descriptors rather than `FILE*`, whose symbol names differ
- no varargs, so no `printf`; decimal output is written out by hand
- `pthread_attr_t` as an opaque buffer larger than any platform's
- no signal handling at all

A prototype was measured before this change was made. On macOS arm64, and on
Linux aarch64 under Docker (Ubuntu 24.04, glibc, clang 18), with identical
results on both, it passed all 30 compiled tests against the interpreter's
expectations, and the compiler linked against it compiled itself
byte-identically.

**Why the stack is checked rather than caught.** The C runtime reported
exhaustion from a SIGSEGV/SIGBUS handler running on an alternate stack.
`struct sigaction`, the value of `SA_ONSTACK`, and the number of `SIGBUS` all
differ between macOS and Linux, and target-independent IR cannot express any of
them. So the thread records a limit when it starts, 256 KB above the bottom of
its stack, and each function compares its frame address against it. The cost
is one call per function entry. Measured against the C handler, exhaustion is
reported at exactly the same depth for every `L0_STACK_MB` tried, from 1 to
512.

The big stack stays, and is still sized by `L0_STACK_MB`. The compiler does
not need it: at `-O2`, LLVM turns its recursion into loops, and it compiles
itself on 1 MB. User programs do. Recursion that LLVM cannot rewrite, such as
rebuilding a list through `cons`, costs 32 bytes a frame on arm64, so the
default 8 MB stack fails on a 1 MB input that 512 MB handles. macOS could set
that size at link time, but Linux has no equivalent, so it is still a thread.

**A trap in the transition, and why this landed with a fresh seed.** The
compiler now emits the checks, but the seed predates them, so a compiler built
from it produces programs with no stack checks. Linked against the new
runtime, those programs crash with a bus error on deep recursion rather than
reporting it. Nothing in the test suite would have caught this, because
`--compiled` bootstraps from source first. It showed up only through
`l0 build`, which uses the installed compiler. So the seed was refreshed in the
same change, and there is no commit at which the installed toolchain loses the
error.

`tests/lang/err_stack` is new. Stack exhaustion had no test before.

**What stays C.** Only stage 0. `runtime/l0core.c` is now compiled for the
interpreter alone, and `tools/install.sh` compiles no C at all. `l0rt.c` is
linked by nothing; roadmap item 0004 deletes it and moves `l0core.c` under
`stage0/`.

---

## A new goal, and the agent that uses L0 is the one that changes it

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what L0 is for, and how it changes.

**The goal.** The README opened with a goal that has been met: "L0 does not
aim to be fast, general, or pleasant for humans. It aims to be expressive
enough to express its own compiler." "Purity is a property, not a premise"
below stopped the spec from treating self-compilation as the only goal, but
left the direction to whatever applications happened to request. The goal is
now stated in its own right, in three parts:

- **Compiled.** L0 compiles to native code through LLVM and is never
  interpreted at run time. That is the only sense in which it aims to be fast.
  Tail calls, inlining, and register allocation are left to LLVM, so L0 does
  not implement optimizations itself, and speed alone does not justify a change.
  Section 8 still leaves tail-call elimination unspecified; this is a statement
  of where the work lives, not a new guarantee.
- **General purpose.** L0 should express ordinary programs, not only its own
  compiler. Memory management and I/O come first, and the direction is for
  compiled programs to stop needing the C runtime in `runtime/`. That makes the
  cost notes in section 10.3 and in "Output before input" below live questions
  rather than hypothetical ones.

  "Without the C runtime" means no C source in a compiled program, not no
  libc. libc stays as the interface to the operating system, because on macOS
  it is the only supported one: Apple does not keep the raw system call ABI
  stable, which is why Go calls libSystem there rather than the kernel. A
  program that makes raw system calls would be Linux-only, and nothing in the
  goal is worth that.
- **Written for agents, not humans.** This is the one part of the old "does not
  aim" list that survives. L0 is read and written by an agent, so whether code
  comes out correct, and whether the checker catches it when it does not,
  outweighs brevity and familiarity.

Self-compilation stays the one property no change may cost.

**The process.** The request loop is retired: the `l0-limits` skill in
scaffolded projects, `l0 request` and `l0 submit`, the `requests/` inbox, and
triage here by the `l0-evolve` skill. It was too tedious to operate, and the
agents in those projects were too quick to work around a limitation instead of
reporting it.

The loop's own rules made that the expected outcome. The toolchain was
read-only, a workaround had to exist before a request could, and a cost that
was constant per use site was to be worked around "however tedious". Two
results of that are already on record. The compiler carries nine
near-identical result types for want of generics, which never qualified. And
the hell0 project shipped a greeting program that "does something adjacent to
what was asked, and its test suite passes" (see the entry below). A workaround
that ships absorbs exactly the pressure a language change needed.

Now the agent that writes L0 in this repository also changes it, and when L0
cannot express something the answer is to change L0. A change is still earned
by code — L0 in this repository that it makes possible, or makes harder to get
wrong — and the spec-first order, the two-step rule, and the frozen stage 0 are
unchanged. Those rules moved from the deleted `l0-evolve` skill into
`l0-bootstrap`, so that one skill covers every change that has to survive the
bootstrap.

`l0 init` still scaffolds a project with the spec, the examples, the prelude,
and the `l0-code` skill. The `AGENTS.md` it copies now tells an agent to name a
limitation plainly rather than ship a narrowed version of the task, since
nothing any longer carries a report back here.

**Earlier entries** cite `requests/`, `l0-limits`, and `l0-evolve`. They are
left as written; the files are in git history. Where a decision rested on the
loop's tests for change — constant per use site, three unrelated places, a
host-protocol question rather than a language one — it is to be re-argued
rather than inherited, as "Purity is a property, not a premise" already said of
purity.

**What did not change, deliberately.** The restrictions formerly under "What
makes a good feature" still stand: one-level `match` with no wildcard, no type
inference, `list` as the only parametric type, and no function values. Their
reason is restated for the new goal rather than dropped. They keep the checker
simple and every error local, which serves an agent writing L0 as much as it
served the bootstrap. Breaking one is allowed, and should buy something
substantial.

---

## Output before input is an accepted blocker

**No semantic change. L0 is exactly the language it was before this entry.**
Section 9 still has the host read standard input to end of file, then evaluate
`(main input)`, then write the result, and nothing in the grammar, the type
rules, the runtime, or the emitted IR has moved.

What this entry records is that the blocker behind a future change to that
ordering has been demonstrated, checked here, and accepted. It is written now
because the demonstration lives in a project that may change, and because the
same blocker arrived twice from the hell0 project, as requests `hell0-0001`
and `hell0-0003`, and was argued from scratch both times. The requests
themselves were retired with the request loop (see the entry above); what
mattered in them is quoted here.

**The blocker.** From `hell0-0003`, which states the task and the obstacle:

> The task: ask the user for their name, then greet the name they gave. One
> turn — write, then read what the writing caused.
>
> No L0 program can do this, and the obstacle is not syntax, so there is no
> code that fails to compile. What fails is the order.

The nearest expressible program returns the question and the answer together,
and so "prints `What is your name? Hell0, Ada!` — a question printed after its
own answer was consumed. The bytes are in the right order on screen and in the
wrong order in time."

**The measurement**, which is the part that would otherwise be unrecoverable.
`test/ordering/measure.sh` in that project supplies the answer immediately and
delays only end of file, so the two hypotheses predict outputs three seconds
apart. Reproduced here:

```
answer is readable at t+0; end of file comes at t+3s

  t+2.98s  got: Ada
  t+2.98s  |end

first output byte at t+2.98s.
```

> The answer was readable at t+0. No output byte appeared until t+2.98, when
> EOF arrived. [...] The program cannot emit a prompt while the user is still
> able to respond to it, on any input, because evaluation has not begun.

The script exits 0 while the limitation holds and nonzero if output ever
appears early, so it is also the check that would tell us this had been
fixed. `nm` on `lib/libl0rt.a` agrees from the implementation side:
`l0_read_stdin_list` and `l0_write_result` are the only symbols that touch the
byte channel, so there is one read and one write and no way to interleave them.

**What the workaround costs.** There is no workaround that performs the task:

> **The program cannot be written.** Not awkward — impossible. The requirement
> is that the program's output influence its own input. Section 9 orders all
> reading before all evaluation, so the two cannot both hold, and no amount of
> structure on the byte channel changes it: a format says what bytes mean, not
> whose turn it is.
>
> The cost is not line count. It is that the shipped program does something
> adjacent to what was asked, and its test suite passes, because the tests were
> written from the same contract.

What shipped is a program that greets a name on stdin and never asks for one —
"honest and it is not the task. An observer watching it run is never asked
anything." A bash wrapper that did the asking was tried first and rejected,
for a reason worth keeping: the turn lived in the shell, so the L0 half could
not decide whether to ask, or ask a second question whose wording depended on
the first answer.

> This generalises past greeting: a confirmation prompt, a menu, a retry on
> invalid input, and progress during a long run are all the same limitation.

**Why this is not the ordinary host-protocol case.** It was the one carve-out
in the `l0-limits` skill, and that carve-out existed because of this same
project's earlier skill note: structure says what bytes mean, it cannot say
whose turn it is. The precedent for reaching for a format instead of a feature
is strong — see "Input bundle" and "Compiler output protocol" below, three
problems in a row that looked like they needed a primitive and needed none —
but all of that evidence comes from the compiler, which is a batch program that
never wanted a turn. It is evidence about content and silent about ordering.

**What is accepted, and what is not.** The blocker, and the general shape of
the fix: `main` stays a pure function from bytes to bytes and is re-run on a
longer prefix of the transcript each turn, recomputing rather than resuming, so
nothing captures a continuation and determinism and replay are preserved.

Not accepted, twice now, is putting the turn directive in the type system — a
predeclared `Turn`, or the `Step`/`Done`/`More` of `hell0-0003`. Section 7.1
does not group type and constructor names, and "Why types and constructors are
not grouped" below records that as structural rather than an oversight, so a
predeclared constructor breaks every program that already used the name, with
no shadowing escape. The directive belongs on the byte channel, where the
compiler already puts `O` and `E`, which costs no name, no second entry point,
and no checker case.

**What it will cost when it is made**, so that the price is on record:

- **Sections 1 and 9.** The purity boundary moves. Individual `main` calls stay
  pure and the language still has no I/O primitive, so section 8 is untouched
  and evaluation order stays unobservable. This is why a host loop is much
  cheaper than an effect in expression position.
- **Section 10.3, which asks to be costed directly.** `hell0-0003` is the first
  request to do so, and its answer is accepted: re-entry is bounded by the turns
  the program asks for, the process still runs once and exits, so the bump arena
  stays correct, and a program demanding unboundedly many turns exhausts the
  heap — already a runtime error under section 8, already reachable through
  unbounded recursion. What is given up is the guarantee that total allocation
  is bounded by a single evaluation. A fresh process per turn avoids even that,
  which is why the out-of-process loop is the cheaper first step.

Streaming `main`'s result as it is produced was considered and is a different
change. It would fix progress reporting and not prompting, since stdin is still
consumed before `main` is called, and doing it properly needs non-strict
evaluation, which section 8's strictness rules out as load-bearing.

*Qualified later, by "A new goal": I/O is now a goal in its own right rather
than something an application has to prove it needs. The blocker and the
measurement above stand. The preference for keeping `main` pure and moving
the turn into a host loop was argued under the old goal, when the aim was to
change as little as possible, and is one candidate to re-argue rather than the
settled shape.*

---

## Purity is a property, not a premise; self-compilation is not the only goal

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what the spec claims about its own
permanence, which had started to govern decisions it was never meant to govern.

**The blocker.** Two sentences in the spec's opening — "L0's single goal is to
be able to compile itself" and "Everything in this document exists because it
serves that goal" — were written before self-hosting was reached. They are a
true account of how v1 came to be and a false account of what governs L0 now.
The `l0-evolve` skill already says the opposite: "Self compilation supplied
that pressure until it was reached; applications written in L0 supply it now."
A spec and a skill that disagree about what justifies a change is not a
cosmetic problem, because the spec wins, and the spec's version rejects on
sight any request arising from an application rather than from the compiler.

That is not hypothetical. `requests/hell0-0001-interactive-input.md` asks for
interactive prompting, which self-compilation will never need: the compiler is
a batch program. Under the old opening the request is refused without reading
the evidence. Under the new one it is judged on whether the blocker is real.
The ambiguity was deciding requests by itself, which is the one thing an
ambiguity must not be allowed to do.

**Smallness.** No rule anywhere required L0 to stay small, and none does now.
What exists is a bar for change — it grows when real code cannot be written
without the addition — which is a justification requirement, not a size cap.
The opening now says smallness is a description rather than a vow, so that the
bar is argued about on its own terms.

**Purity.** Three rules leaned on purity, two of them silently, and the fix is
to name the dependency at each site rather than to weaken any of them:

- Section 8 derived the unobservability of evaluation order from purity. The
  left-to-right rule itself never depended on purity and is unchanged; what
  purity buys is an implementation's freedom to reorder pure arguments. That
  is now stated as the thing a change would cost.
- Section 10.3 said the bump arena is correct "because an L0 program is a
  single pure evaluation that runs once and exits". Purity was doing no work
  in that sentence. The arena is correct because the run is *bounded*, and an
  impure L0 that still ran once and exited would not disturb it. Section 10.3
  now says so, and names re-entry and unbounded running as the changes that
  would put a collector back on the table. This is a real finding rather than
  a rewording: it means a resumable entry point is an allocator question,
  which nothing in the spec previously said.
- Section 1 asserted purity flatly. It now adds that the impurity lives in the
  host by v1's choice of boundary, and points at the two sections above.

The claim that purity was merely the cheapest route to bootstrapping does not
survive the record, and is not the reason for this entry. Purity was a
deliberate placement — see "An entry point and a host contract" below: "this
adds no I/O to L0 itself: `main` is still a pure function, and the impurity
lives entirely in the host." It remains load-bearing. The point of naming what
rests on it is that a future proposal can price the change instead of
discovering the dependencies one broken derivation at a time.

**What did not change, deliberately.** The language must still be able to
compile itself. That is now stated as the one property no change may cost,
which is a stronger and narrower claim than "everything serves that goal": it
forbids a change that breaks self-hosting, and permits one that merely fails to
advance it. Every restriction in "What makes a good feature" also still stands;
this entry loosens the stated *purpose* of the language, not the bar any
individual change has to clear.

A program may now define a function the prelude already defines. The program's
definition wins throughout the program; the prelude goes on calling its own.
Spec section 7.1 states the rule, 9.1 states how a compiler is told where the
boundary is, and 10.2 gives the prelude its own symbol prefix.

**The blocker.** Before this, the prelude occupied the same flat namespace as
the program, so a project that had written its own `length` could not compile
at all:

```
clash.l0:1:1: error: function length is already defined
```

That makes every addition to `lib/prelude.l0` a breaking change for programs
that already exist, and the hazard grows with the prelude: the more it holds,
the likelier any given project has already used one of the names. This is the
"cost grows with the program" case in the `l0-limits` skill, and it is the one
cost of prelude growth that the emitted-linkage change immediately before this
did not touch. Compiled size was the other, and is now nothing.

The workaround was `l0 build --no-prelude`, which trades one name for the
whole library, and which the shipped `AGENTS.md` did not even mention.

**Why two groups and not a module system.** A general module system was
considered and rejected. Imports would mean path resolution inside a compiler
that is by definition a pure function from bytes to bytes, so the work lands in
the driver either way; what it would buy is separate compilation, which this
project does not want, because whole-program checking is exactly what lets the
checker do without inference. Measured by the `l0-limits` test, needing to name
every file on one command line is a cost that is constant per use site. Name
isolation was the only part that was not.

So the addition is deliberately not general: there are exactly two groups, not
n, nothing in a source file can say what it needs or exports, and the grouping
comes from the input protocol rather than from L0 syntax.

*Qualified later, by "Purity is a property, not a premise": "by definition a
pure function from bytes to bytes" describes v1, not a fixed truth. The
argument above is left as it was made, since it is the reasoning that was
actually used. If purity is ever revisited, this rejection is one of the
things that has to be re-argued rather than inherited.*

**Why the program's definition does not simply replace the prelude's.** The
cheaper rule — one namespace, last definition wins — was rejected because it
is monkey-patching. A program defining its own `list_eq` would silently change
what the prelude's `any_eq` and `index_of` do, and nothing would report it.
Two scopes cost a symbol prefix and catch that at the point of definition
instead, which is the trade this project has taken every other time it came
up.

**The compiler itself is still compiled as one group.** `tools/l0` marks the
prelude for a user's program; `tools/l0c`, which builds this repository and
runs its tests, does not, because when the compiler is built `lib/prelude.l0`
genuinely is part of the program rather than a library beneath it. So
`bootstrap/stage2.ll` carries `@l0_f_length` and not `@l0_p_length`, and the
grouping is exercised by `tests/compiler/prelude_scope` and
`tests/compiler/bundle_prelude` rather than by the bootstrap. This also kept
the two steps apart: the compiler learned to read `#prelude` and the seed was
refreshed before any driver started writing it, so no fresh clone ever sees a
header its only compiler cannot parse.

**Why types and constructors are not grouped.** A `match` arm names a
constructor without naming its type, so constructor resolution has to be
global for one-level patterns to resolve at all, and `ty_eq` compares types by
name, so two same-named types could not be told apart. Grouping function names
needs neither. The restriction is recorded in 7.1 so that a later attempt to
group them starts from the reason rather than from the omission.

---

## Emitted linkage — resolved

Every function except `main` is now emitted as `define internal`, so the
prelude no longer costs anything in a program that does not use it.

No language change. The spec does not describe linkage, and it still does not:
this is a fact about the emitter, recorded because the reasoning behind it is
what makes the next question answerable.

The old emitter gave every function external linkage. Nothing can remove an
externally visible symbol, so a hello-world compiled with the prelude carried
all 30 prelude functions into its object file at 10704 bytes, of which it
called none. With internal linkage on everything but `main`, LLVM's `-O2`
deletes the unreachable ones and the same object is 1168 bytes.

`main` stays external because [../runtime/l0rt.c](../runtime/l0rt.c) calls
`l0_f_main` by name, and `@l0_main_ret_kind` stays a plain global for the same
reason. Those two symbols are the entire interface a compiled program exposes;
a program is otherwise a closed module, which is what makes internal linkage
correct rather than merely convenient.

This was prompted by the observation that `lib/prelude.l0` will keep growing
and that every program pays for all of it. Half of that was true and is now
false. What remains true is that the prelude occupies the same flat namespace
as the program, so a project that defines its own `length` cannot compile:

```
clash.l0:1:1: error: function length is already defined
```

That is the cost that actually grows with the prelude, and it is a language
question rather than an emitter one. Recorded here as open, deliberately
separate from this change. Compile time is not part of the picture: the whole
prelude adds about 2 ms to a hello-world.

The seed was refreshed in the same change, since the emitter's output shape
changed. The fixpoint held first: a seed built before this change compiles the
new compiler to `stage1.ll` with the old linkage, and that compiler then
reaches `stage2.ll == stage3.ll` with the new.

---

## Self-hosting reached

`compiler/*.l0` compiles itself to a byte-identical fixpoint, and
`bootstrap/stage2.ll` is checked in as the bootstrap seed. Verified by
removing `stage0/` entirely and rebuilding the compiler from the seed alone.

No language change was needed to get here. L0 v1 as specified was sufficient
to express its own compiler, which was the entire point of the design.

Two things are worth recording because they were predicted and held:

**The monomorphism pressure never became a blocker.** The compiler carries
nine near-identical "value or error" result types that a parametric data type
would collapse into one. That was annoying and never worse than annoying, so
parametric data types remain unjustified. The blocker that would justify them
has still not appeared.

**Nothing needed I/O.** The compiler is a pure `(list int) -> (list int)`
function, and everything that looked like it wanted a primitive turned out to
be a protocol on the single channel instead.

---

## Input bundle — resolved

Diagnostics now report `file:line:column` rather than a line number in the
concatenated stream, and again no language change was needed.

Input may optionally begin with a table of byte offsets and paths:

```
#l0bundle
0 util.l0
41 main.l0
#source
<the concatenated file contents>
```

The compiler maps a diagnostic's byte offset back to the file containing it
and measures line and column from that file's start.
[../tools/l0c](../tools/l0c) builds the bundle. Input that does not begin with
`#l0bundle` is treated as a single unnamed source, so piping a bare file still
works and the bootstrap is unaffected.

This was recorded as an open question and became worth fixing the moment the
compiler was pointed at a real multi-file project: an error on line 2 of the
second file was reported as line 3, which points at nothing and sends the
reader to the wrong place entirely.

That makes three problems in a row that looked like they wanted an I/O
primitive and were solved instead by putting a little structure on the single
byte channel. The pattern is worth trying before reaching for a language
feature.

---

## Compiler output protocol — resolved

The question of how a compiled program distinguishes "here is my output" from
"I failed, and here is why" is settled, and needed no language change.

`main` returns a **tagged stream**: `O` and a newline followed by LLVM IR, or
`E` and a newline followed by diagnostics, one per line.
[tools/l0c](../tools/l0c) strips the tag, routes the remainder to stdout or
stderr, and sets the exit status, so callers see an ordinary unix compiler.

A printable tag was chosen over a leading zero byte so that raw compiler
output stays readable under `head` while debugging.

This confirms the reasoning recorded when the question was opened: a pure
`bytes -> bytes` function plus a slightly richer host protocol goes much
further than it appears, and the things that look like they need I/O
primitives usually do not.

---

## v1 — initial spec, superseding the seed

[L0.md](L0.md) replaces [../seeds/spec.md](../seeds/spec.md) as the single source
of truth. The seed is kept unchanged for history.

### Added

**String literals.** `"add i64 "` denotes a `(list int)` of byte values.
*Reason:* the compiler's entire output is text. Without literals, every emitted
fragment would be a hand-written `cons` chain, which is unreadable and
unmaintainable at the scale of a code generator.

**Parametric lists, `(list T)`.** The seed had a single `list` type meaning
"sequence of int". *Reason:* a compiler needs a list of tokens and a list of
declarations, not just a list of integers. This is the one generic type
constructor in L0; user data types are monomorphic, which avoids needing
unification or type inference anywhere in the checker.

**`data` declarations and `match`.** Tagged unions of fixed-arity constructors,
with one-level-deep exhaustive pattern matching. *Reason:* an abstract syntax
tree is a sum type. Without one, the AST would have to be encoded into a flat
`(list int)` with a hand-rolled allocator, making every access O(n).

Patterns are deliberately restricted to one level with no wildcard arm, so
exhaustiveness checking is a matter of counting constructors and `match` codegen
is a jump table. Nested patterns would require a pattern-match compilation
algorithm in the self-hosted compiler, which is a large amount of work for
convenience alone.

**An entry point and a host contract.** A program declares `main`, the host
supplies stdin as a byte list and writes the result to stdout. *Reason:* the
seed spec described a language in which nothing could be run or tested. Note
that this adds no I/O to L0 itself: `main` is still a pure function, and the
impurity lives entirely in the host.

**A compilation target (section 10).** Value representation, generated symbol
names, and the runtime interface. *Reason:* the L0 compiler must emit exactly
this, so it is part of the language's contract rather than an implementation
detail. Pinning it down also allows the "every value is an `i64`" simplification
to be relied upon rather than rediscovered.

### Changed

**`int` is 64-bit, not arbitrary precision.** *Reason:* the seed promised
arbitrary precision, which means shipping a bignum library in the runtime before
a single L0 program can run. GMP is not installed, and a self-hosting compiler
never needs a value above 2^63. Keeping the spec honest matters more than
keeping it ambitious, because the spec is an agent's only source of truth and an
aspirational claim here would become a silent correctness bug.

**`nil` is an expression form, not a builtin.** It is now written `(nil int)`
with an explicit element type. *Reason:* with parametric lists, bare `(nil)` has
no determinable type. The alternative was bidirectional type checking to
propagate an expected type inward, which is real machinery and interacts badly
with recursion and `if` branches. An explicit type argument keeps the checker
completely inference-free.

**Names are split into lower and upper by first character.** Functions,
parameters, and bindings are `[a-z_]...`; types and constructors are `[A-Z]...`.
*Reason:* it lets a reader distinguish a constructor from a variable with no
context and no symbol table, which keeps both the parser and the eventual
self-hosted checker simple.

**`int`, `bool`, and `list` joined the reserved words**, alongside the seed's
`def`, `if`, `let`, `true`, `false`, plus the new `data`, `match`, and `nil`.

### Resolved ambiguities

The seed spec did not settle these. Each was decided to keep the language
deterministic and the checker simple; any of them can be revisited.

**Argument evaluation order** is left to right. *Why it matters:* L0 is pure, so
order is unobservable except for which runtime error fires first. Specifying it
makes failure deterministic, which in turn makes error tests reproducible.
*(Still the rule. See "Purity is a property, not a premise": the ordering does
not depend on purity, so a change to purity would cost the unobservability and
leave the left-to-right rule standing.)*

**`mod` takes the sign of the dividend.** The seed said division truncates
toward zero but did not say what `mod` does with negatives. Truncated division
implies the remainder follows the dividend, so `(mod -7 2)` is `-1`. This is what
LLVM's `srem` and C both do, so it is free to implement.

**Overflow wraps** rather than trapping, including the three cases that would
otherwise be undefined: `(div INT_MIN -1)` is `INT_MIN`, `(mod INT_MIN -1)` is
`0`, and `(neg INT_MIN)` is `INT_MIN`. *Why:* wrapping maps directly onto LLVM
arithmetic at zero cost. The three special cases are called out because LLVM's
`sdiv` and `srem` treat them as undefined behavior, so the runtime must handle
them explicitly to keep the language total.

**`let` shadowing is allowed.** An inner binding shadows a parameter or an
enclosing binding of the same name. *Why:* forbidding it forces gratuitously
unique names in deeply nested code, and accumulator-passing style produces a lot
of nesting.

**Locals and functions occupy separate namespaces** (section 7). A lower name in
call position is always a builtin or a `def`; a lower name anywhere else is
always a local. *Why:* L0 has no first-class functions, so a local can never be
called and a function name can never be a value. Making the rule syntactic
removes an entire class of resolution ambiguity, and it means a parameter named
`length` does not shadow a function named `length`.

**Shadowing a builtin is legal but the builtin always wins** in call position,
which makes a `def` named `add` uncallable. Rejecting it outright would be
defensible; allowing it keeps the resolution rule uniform, and it is a lint
concern rather than a correctness one.

**`eq` remains int-only.** Comparing lists or data values is a function written
in L0. *Why:* structural equality on arbitrary types is a polymorphic builtin
whose implementation needs runtime type information, which the "every value is
an `i64`" representation deliberately discards.

**Duplicate declarations are errors**, enumerated in section 4: duplicate
functions, duplicate types, duplicate constructors even across different types,
and duplicate parameter names. Constructors share one global namespace because
`match` arms name a constructor without naming its type, so the constructor has
to determine the type on its own.

**A `data` declaration needs at least one constructor.** An empty one would
declare an uninhabited type, which is useless here and would make `match`
exhaustiveness vacuous.

**`match` has no wildcard and no default arm**, and every constructor must appear
exactly once. *Why:* adding a constructor to a `data` type then becomes a compile
error at every site that must handle it, which is the property that makes
evolving the compiler's own AST safe.

**Recursive and mutually recursive data types are allowed**, since trees are the
point.

**String literal details.** The escape set is exactly `\n \t \r \\ \" \xHH`; any
other escape is an error. A raw newline inside a string literal is an error, so
that an unterminated string is caught on its own line instead of swallowing the
rest of the file. Literals produce unsigned bytes, never negative elements.

**Integer literal details.** A literal must fit in 64 bits, and a `-` is part of
a literal only when immediately followed by a digit. `- 3` is an error rather
than a subtraction, because `-` is not a name in L0.

**Runtime errors exit with status 70** and write one line to stderr, producing no
stdout. 70 is `EX_SOFTWARE` from `sysexits.h`, chosen so it cannot be confused
with a type error (status 1) or with a signal.

**Stack and heap exhaustion are reported as runtime errors** in the same form.
They are the only two failures a well-typed program can suffer that are not in
the list of four, and since L0 has no loops and no tail-call guarantee, deep
recursion is a realistic outcome rather than a pathological one.

**Output bytes are reduced modulo 256.** `main` returns a `(list int)` whose
elements are full 64-bit integers, so out-of-range elements need a defined
behavior. Truncating is quieter than erroring and matches how the bytes were
produced on the way in.

**Multiple source files are concatenated.** Declaration order is already
irrelevant, so file splitting is an editing convenience with no semantics. This
avoids designing a module system, which the bootstrap goal does not require.
