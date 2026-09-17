---
name: l0-limits
description: Decide whether a missing L0 language feature should be worked around or reported as blocking, and write a feature request when it is blocking. Use when L0 cannot express something, when reaching for a workaround for a language limitation, when tempted to modify the L0 toolchain, or when judging whether a limitation blocks the work.
---

# When L0 cannot express something

L0 is small, and grows only when real code cannot be written without the
addition. That is a bar for change, not a cap on size, and smallness is a
description of L0 rather than a promise it keeps: a limitation you can
demonstrate is worth reporting however small the language happens to be.
Hitting a wall is expected and is useful information.

Your program counts as the real code. Self-compilation is the goal that shaped
L0 and the one property no change to it may cost, but it was reached, and it is
no longer the only source of pressure — a blocker you hit in an application is
grounds for a change the compiler would never have needed.

Your job is to tell three cases apart:

- **a missing idiom**, which you work around and move on
- **a missing feature**, which you work around *and* write up as a request
- **a missing capability**, where nothing you can write does what was asked:
  you write the request, ship the closest honest thing, and say plainly that
  it is not what was asked for

You keep working in all three. What differs is whether a request comes out of
it, and whether the user has to be told.

**The L0 toolchain is read-only.** Do not edit the installed prelude, the
compiler, or anything under the install prefix, and do not vendor a patched
copy. The output of hitting a limit is working code plus, when warranted, a
document. Changing the language happens in the L0 repository, by a human who
has your request in hand.

## First, check the task survived

Before classifying anything, write down what the program must do in terms an
outside observer could check, and confirm that the code you are about to ship
still does it.

A workaround changes *how* something is done. If it changes *what* is done, it
is not a workaround, and being short or idiomatic does not make it one. So:

- Would someone watching the program run agree it did the thing that was
  asked?
- If not, who decided to change the thing that was asked?

If the answer to the first is no, stop treating it as a cost question. You
have the *cannot be written at all* entry in the cost test below, you say so
in your reply instead of reporting the work as done, and **the screens in the
next section do not apply**: they sort limitations by subject, and a task you
cannot perform is not a subject.

This is the failure this skill exists to prevent, and it is worse than a
wrongly filed request. A bad request costs a maintainer a few minutes and gets
declined. A program that quietly does something adjacent to what was asked
costs whoever believed it, and there is nothing in a passing test suite to
catch it, because the tests were written from the same misreading.

## Next, check it is really a language problem

Most walls are not. In the language's own history, three separate problems
looked like they needed a new primitive and none of them did.

**Is it about getting data in or out, and does all of that data exist before
the program starts?** File names, several inputs, arguments, exit status.
L0's contract is bytes in, bytes out, and the fix is almost always to put more
structure on those bytes and let the program on the other side deal with it.
The L0 compiler reports errors, names files in diagnostics, and distinguishes
success from failure through exactly this route, and needed no language change
for any of them.
→ **Not a feature request.** Design a format.

**The exception is ordering.** The host reads stdin to end of file, evaluates
`main`, and only then writes the result. So every byte the program reads was
chosen before it emitted any, and no byte it emits can appear before it is
finished. If what the program must read depends on the user having seen what
it wrote — a prompt, a confirmation, a menu, a retry on bad input, anything
with a turn in it — then no format fixes it. Structure says what bytes mean;
it cannot say whose turn it is. Progress during a long run is the same fact
from the other side. The compiler, which is all of the evidence for the
paragraph above, is a batch program that never wanted a turn, so it is
evidence about content and silent about ordering.
→ **Candidate request.** Name the two events that need reordering.

The question to ask is not "is this about input?" but "does the input depend
on my output?". Answering the first one and stopping is how a task gets
quietly redefined.

**Is it a function you could just write?** There is no `map` or `filter`
because there are no function values, but a specialised version is usually
under ten lines. The prelude is small on purpose.
→ **Not a language request.** Write the function. If it is broadly useful,
request a *prelude* addition, which is far cheaper than changing the
language and is a different kind of ask.

**Is a prelude function nearly right?** Define your own with the same name.
It shadows the prelude's throughout your program, and the prelude keeps using
its own, so this is neither a collision nor a reason to invent a new name.
→ **Not a request of any kind.**

## Then apply the cost test

Write the workaround first. A request must quote code that exists, not code
you imagine writing. If the workaround turns out to be fine — it passes the
gate above and you would ship it — there is nothing to report.

Then ask what the workaround costs:

**The program cannot be written at all → request, and say so out loud.**
Uncommon, and the screens above do rule out most apparent instances, so the
bar is a demonstration rather than a feeling. Name the requirement, name the
two things that cannot both hold, and measure it. "I could not find a way" is
not a demonstration. "The host finishes reading stdin before evaluation
begins, and here is the timestamped run showing the question printed after the
answer was consumed" is.

Once you have that, file it. Do not go back around the screens looking for the
verdict you expected; a demonstrated impossibility does not become more
certain by sitting on it, and being told the limitation was acceptable is
cheap compared to shipping a program that does something else. This is also
the one cost the user has to hear about directly, because it is the one where
the thing they asked for is not what they are getting.

**Constant per use site → work around, no request.** A few extra lines each
time is not a blocker, however tedious. The L0 compiler carries nine
near-identical result types because the language has no generics; each costs
four lines, and that never justified a language change.

**Loses a correctness property → candidate request, even if it is short.**
If the workaround means encoding a type as an int and losing type checking,
or abandoning exhaustiveness so that adding a case no longer produces an
error, the line count is not the point. Safety lost is worth more than
keystrokes saved.

**Cost grows with the size of the program → candidate request.** Anything
where each new case forces edits in several unrelated places, or where the
work is superlinear.

**The same workaround appears in three unrelated places → candidate
request.** Cheap but pervasive is its own kind of evidence, and it is the one
case where a constant cost still justifies a request.

## Writing the request

```bash
l0 request short-slug        # creates l0/requests/NNNN-short-slug.md
# fill it in
l0 submit l0/requests/NNNN-short-slug.md
```

Fill in every section. `l0 submit` refuses a request whose code blocks are
still empty, because the person receiving it has to weigh your problem
against keeping the language small and cannot do that without the code.

`l0 submit` prints a `cursor://` deeplink that pre-fills a triage prompt in
Cursor. Clicking it is the operator's job, not yours: it lands in whichever
window is active and always waits for confirmation. Print the link and say
it is ready. If `L0_HOME` points at the L0 repository on this machine, the
request is also copied into its `requests/` inbox.

Be specific about the smallest change that would help. "Generics" is not
actionable; "a `Result` type parameterised over one type variable, with no
inference, so that `(Result Token)` names a type" is. Propose the least the
language could gain and still solve your problem.

Say which of L0's deliberate restrictions your request breaks, if any:

- `match` patterns are one level deep with no wildcard, so adding a
  constructor is a compile error everywhere it must be handled
- there is no type inference; every expression's type comes from itself
- `list` is the only parametric type constructor, so nothing needs
  unification
- there are no function values, so name resolution is purely syntactic

Each of these keeps the compiler small and the checking strict. Breaking one
is allowed but has to buy something substantial, and saying plainly which one
you are pushing on makes the request much easier to judge.

## What good and bad requests look like

**Bad.** "L0 needs higher-order functions so I can use map." No workaround
attempted, no cost shown, and the smallest useful change is unstated. A
ten-line recursive function would have solved it.

**Bad.** "L0 needs file I/O to read a config file." This is the data-in
question above. The host can pass the config on stdin in a bundle.

**Good.** "The program must ask for a name and then greet it. The workaround
prints the question and the greeting together: with the answer supplied at
once and end of file held off three seconds, `{ printf 'Ada\n'; sleep 3; } |
prog` shows both lines arriving only after that delay, so the question is
printed after the answer was read, always. No format fixes the order, because
the host reads
stdin to end of file before evaluating `main`. The smallest fix is a host
protocol that evaluates `main` more than once, each result becoming the next
input; it needs no change to the type system."

Those two are the same topic and opposite verdicts. The config file exists
before the program starts; the name does not exist until the user has read
something. Sorting on the topic gets the second one wrong every time.

**Good.** "Encoding a tagged value as `(list int)` and decoding it by hand
appears in six places in `parser.l0`, and each new tag needs edits in the
encoder, the decoder, and every reader, with nothing checking they agree.
The workaround is in `parser.l0:40-120`. The smallest fix is parametric data
types with one type variable, no inference; it breaks the 'list is the only
parametric constructor' restriction."

The difference is not tone. It is that the good ones contain evidence, name a
cost that grows or a requirement that cannot be met at all, and propose the
least the language could change.

## This is not for skill improvements

If you changed a shipped skill because the practice it taught was wrong or
incomplete, that is a different document. Language requests change the spec;
skill notes change what `l0 init` copies. See the `l0-code` skill, and start
one with `l0 request --skill short-slug`.
