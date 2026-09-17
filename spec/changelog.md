# L0 specification changelog

Every change to the language is recorded here, with the reason it was made. The
spec itself ([L0.md](L0.md)) says only what L0 *is*; this file says why.

New entries go at the top.

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
