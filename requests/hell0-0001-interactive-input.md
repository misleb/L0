# Feature request: interactive-input

Status: draft
Project: hell0

## What could not be written

A program that asks the user a question and then uses the answer. The task was
"prompt for a name, then print `Hell0, <name>!`". There is no L0 that does it,
so what follows is the closest legal program and the demonstration that it does
not ask anything.

```
(def greet ((input (list int))) (list int)
  (let a (push (prompt) (nil int))
    (rev (push (greeting (name_from input)) a))))
```

This is legal and type checks. It is also not a prompt: nothing it returns is
written until it has already returned, and by spec section 9 it cannot be
called until stdin has been read to end of file. The bytes of the question are
therefore always written after the bytes of the answer have been consumed. The
ordering is fixed by the host contract, not by how the program is written:

    (def main ((input (list int))) (list int))

    1. read standard input to end of file
    2. evaluate (main input)
    3. write the result

Measured, with the answer supplied immediately and end of file held off for
three seconds:

```
$ { printf 'Ada\n'; sleep 3; } | ./build/hell0 | while IFS= read -r l; do
      printf 't=%ss  %s\n' "$SECONDS" "$l"; done
t=4s  What is your name? Hell0, Ada!
```

The answer was readable at t=0. The question appeared at t=4, after end of
file at t=3. A user at a terminal sees no question, types into what looks like
a hung program, and has to know to send Ctrl-D; only then is the question
printed, directly in front of the answer to it. Step 1 finishing before step 2
begins is what makes this unfixable in the language as specified: no
arrangement of `push`, `rev`, `append`, or output ordering changes it, because
the program has not started running while the input is being collected.

## The workaround actually used

`src/greeting.l0:8-9` and `src/greeting.l0:37-41`, shipped as the answer to the
prompting task. The prompt text became part of the *output*, emitted ahead of
the greeting, and the answer is read from the first line of stdin:

```
(def prompt () (list int)
  "What is your name? ")

(def greet ((input (list int))) (list int)
  (let a (push (prompt) (nil int))
    (rev (push (greeting (name_from input)) a))))
```

Interaction was then obtained *outside* L0, by a host script that does the
asking and feeds the answer back in (`hell0`, in this project's root):

```sh
question=$(printf '#ask\n' | "$prog")   # turn one: what should I ask?
printf '%s' "$question"
IFS= read -r name
printf '#answer\n%s\n' "$name" | "$prog"   # turn two: here is the answer
```

Two invocations of the same program, with the first line of stdin naming which
half of the exchange is wanted. The wording of the question is fetched from the
program rather than written in the script, so it is not duplicated across the
boundary; the price is that the L0 side now needs a directive parser and a
three-case request type to say which half it is producing, at
`src/greeting.l0:20-77`:

```
(data Request
  (AskName)
  (GreetName (list int))
  (Batch (list int)))

(def parse_request ((input (list int))) Request
  (if (is_directive input (ask_directive))
      (AskName)
      (if (is_directive input (answer_directive))
          (GreetName (name_from (drop_line input)))
          (Batch input))))
```

This does prompt, correctly, and is what the project ships. It is also the
whole of the evidence below: the dialogue is in the shell script, and what L0
expresses is one turn of it.

## What the workaround costs

**The program cannot be written.** Not awkward: impossible. The requirement is
that the question reach the user before the answer is read, and the host
contract orders those two events the other way around. Every "workaround"
above either drops the requirement (print the question next to the answer,
which is what shipped and is wrong) or moves the requirement out of L0
entirely (the host script, where the prompting is no longer an L0 program doing
it).

The second one is worth being precise about, because it is the reason this is
not the ordinary "put more structure on the byte channel" case. Structuring
the byte channel works when all the data exists before the program runs; the
host can bundle files, arguments, and exit codes because none of them depend on
anything the program says. Here the *n*th byte of input depends on the user
having read output produced in response to the *(n-1)*th, so there is no
format to design: the missing thing is not structure in the bytes, it is
permission for output to precede input.

A host wrapper does not supply that permission. It relocates the dialogue to
the shell and leaves the L0 program holding one turn of it, at the cost of a
directive vocabulary, a request type, and a parser for it — machinery whose
entire purpose is to let a single-shot program be called twice. That cost is
not constant per use site: it is one case in `Request`, one directive, and one
arm of `parse_request` per question ever asked, plus a turn in the shell script
that knows the order the questions come in. A second question whose text
depends on the first answer means the script, not the L0 program, decides what
to ask next, so the control flow of the conversation lives permanently outside
the language.

## Smallest change that would help

One predeclared data type and one optional entry point. Nothing else, and no
change to `main` for programs that do not use it.

```
(data Turn
  (Ask (list int))        ; write these bytes, then read one line
  (Say (list int)))       ; write these bytes and exit

(def turn ((heard (list int))) Turn)
```

The host loop, when a program declares `turn` instead of `main`:

1. call `(turn heard)`, where `heard` is every line read so far, newline
   separated, and empty on the first call
2. on `(Ask bytes)`, write the bytes, flush, read one line, append it to
   `heard`, and go to 1
3. on `(Say bytes)`, write the bytes and exit

`turn` is a pure, deterministic function from what has been heard to what to do
next, so purity, strictness, and determinism are untouched, and the same
`heard` always produces the same `Turn`. Replaying it with a recorded
transcript is exactly the existing single-shot model, which means golden tests
keep working unchanged: feed the transcript on stdin and compare bytes.

The prompting program becomes the thing that was asked for:

```
(def turn ((heard (list int))) Turn
  (if (is_empty heard)
      (Ask "What is your name? ")
      (Say (greeting (name_from heard)))))
```

Two honest costs. `turn` is re-entered from scratch each round, so an *n*-round
dialogue redoes the parsing of earlier answers and is quadratic in *n*; for
human-paced interaction *n* is small, and this buys the absence of any
continuation or closure. And `Ask` reads one line, which is a host-side
tokenisation choice baked into the language; a byte-count variant would be more
general and less pleasant, and line-at-a-time is what a prompt actually wants.

**A smaller version that does not solve this, stated so it is not mistaken for
one.** Specify that the host writes `main`'s result incrementally rather than
at exit. That needs no new syntax and fixes progress reporting on long runs,
which is a real if separate complaint. It does not fix prompting, because
stdin is still consumed to end of file before `main` is called, so the question
still cannot precede the answer. The ordering is the whole problem; buffering
is not.

## Which deliberate restriction this breaks

**None of the four.** Worth stating plainly, since it is the main argument for
this shape over the alternatives:

- `match` stays one level deep with no wildcard; `Turn` has two constructors
  and both must be handled
- no type inference is needed; `Ask` and `Say` have declared field types and
  `turn` has a declared signature
- `list` remains the only parametric type constructor; `Turn` takes no
  parameters
- no function values are introduced; the resumption is the host calling a named
  `def` again, which is why `heard` is threaded as data instead of captured in
  a closure

What it does add is a second predeclared data type and a second possible entry
point, so the spec grows by a section and the checker by a case. That is the
real price, and it is smaller than any of the four restrictions.

## Alternatives considered

**A host-side protocol on the byte channel.** The standard answer for
input and output, and the one that sent this project down the wrong path. It
works when the data exists before the program starts. It cannot work here: the
content of later input depends on the user having seen earlier output, and no
encoding of bytes reorders the two events. Ruled out above under cost.

**A host wrapper that does the prompting.** Implemented, and shipped as
`hell0` in this project, so this is not a hypothetical and the user does get an
interactive program today. Ruled out as an *answer* because the L0 program is
then not the thing prompting: it answers two separate questions from a shell
script that owns the order they are asked in. It costs a directive and a
`Request` case per question, and the conversation's control flow never lives in
L0 at all.

**An ordinary function, or a prelude addition.** Nothing a function can do.
`prompt`, `name_from`, and `trim` are all ordinary functions and all of them
already work; the missing thing is not a computation, it is the order of two
host operations. No prelude function can move step 3 before step 1.

**Two programs and a shell loop between them.** Splitting the dialogue so each
question is a separate process invocation, with state passed on stdin. This
does work, and is the honest fallback, but it makes every round a process
start and moves the control flow of the conversation into the shell, so the
thing L0 expresses is one turn of it and never the dialogue. Offered here
mainly as evidence that the `turn` proposal is only asking the runtime to do
what the shell loop already does.

---

## Triage

**The blocker is real, demonstrated, and in scope. The proposed shape is too
large, and a smaller one solves the same problem. Sent back for reshaping, not
declined.**

### Why it is in scope at all

This request would have been refused unread a day ago, and the reason is worth
recording. The spec's opening said "L0's single goal is to be able to compile
itself," and interactive prompting does nothing for self-compilation: the
compiler is a batch program that never wanted a turn. That sentence was a true
account of how v1 came to be and a false account of what governs L0 now, and it
was rejecting requests on its own. See "Purity is a property, not a premise" in
the changelog. Under the current opening, self-compilation is the one property
no change may cost, not the only thing a change may serve, so this is judged on
its evidence.

It passes every send-back test in `l0-evolve`. The workaround was written and
shipped, not imagined (`src/greeting.l0`, and the `hell0` script). The cost is
not constant per use site: it is a `Request` case, a directive, and a
`parse_request` arm per question ever asked. It is not an ordinary function, and
the request shows why no prelude addition reaches it. It meets the demonstration
bar in `l0-limits` exactly — requirement named, the two things that cannot both
hold named, and a timed transcript measuring it.

The diagnosis is also correct where it matters most: this is not the ordinary
"put more structure on the byte channel" case, because no encoding reorders two
events. The missing thing is a host *loop*, not a host *format*. That
distinction is the one `0002` was filed to teach, and it holds up.

### Two defects in the proposed shape

**1. `Turn`, `Ask`, and `Say` land in the one namespace that cannot be scoped.**
Section 7.1: "Type and constructor names are not grouped. They share one
namespace across both groups, and a duplicate is an error wherever it appears."
Section 4 makes two constructors of the same name an error even in different
types. So predeclaring `Turn` breaks any existing program that already uses
`Turn`, `Ask`, or `Say` — and it breaks it the way `length` used to break, with
a definition the program cannot shadow its way out of.

That is precisely the blocker the prelude-grouping change was made to fix, and
the fix that worked for functions is recorded as unavailable here: "Why types
and constructors are not grouped" explains that constructor resolution has to be
global for one-level `match` patterns to resolve at all. So this is not an
oversight to patch; it is a structural cost the request does not price.

**2. Re-entry is an allocator question.** Section 10.3: memory is never freed,
and the bump arena is correct because a program is a single bounded run. `turn`
is re-entered many times inside one process with `heard` growing every round, so
allocation accumulates with no upper bound. The request costs the quadratic
re-parse in time and is silent on memory. At human pace neither bites, but a
proposal that makes a program re-entrant has to say which of "bound the rounds",
"free between turns", or "accept the growth" it is choosing.

### The smaller shape

Standardize the loop this project already built, instead of moving it into the
language.

The host re-invokes the compiled program once per turn with the transcript on
stdin. The program returns a tagged directive, exactly as the compiler already
returns `O` or `E`: `A` and a newline followed by the bytes to ask, or `S` and a
newline followed by the bytes to say and exit. The driver loops: run, read the
tag, write the bytes, and on `A` read one line, append it to the transcript, and
run again.

- no predeclared data type, so no constructor collision
- no second entry point, no new checker case, no new spec section beyond the
  host contract in section 9
- a fresh process per turn, so section 10.3 is untouched and the arena question
  does not arise
- `main` keeps its signature, and every existing program is unaffected
- purity, strictness, and determinism are preserved for the same reason the
  request gives for `turn`, and replay against a recorded transcript still works

**This answers the request's own objection to wrappers.** It rules the approach
out because "the conversation's control flow never lives in L0 at all" and "a
shell script owns the order the questions are asked in." That is true of
`hell0`, which hard-codes two fixed invocations — but it is an artifact of that
script, not of the approach. When the program picks the next directive from the
transcript, the program owns the order and the host only loops. The control flow
comes back into L0.

The two shapes are also the same computation. The request concedes that `turn`
"is re-entered from scratch each round, so an n-round dialogue redoes the parsing
of earlier answers," which is the cost it charges against the wrapper. Both are a
pure function from transcript to next action, re-entered from scratch. What
differs is only whether the loop runs in-process, which buys one `exec` per turn
— roughly a millisecond, against a human typing — and costs a predeclared type
in an unshadowable namespace plus an unbounded arena.

### What is needed to proceed

A spec change to section 9 adding the optional loop and the directive encoding,
plus driver and runtime work. No change to the type system, the checker, or the
four deliberate restrictions. If the in-process `turn` is wanted anyway, the two
defects above are what it has to answer first.
