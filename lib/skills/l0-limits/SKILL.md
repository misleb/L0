---
name: l0-limits
description: Decide whether a missing L0 language feature should be worked around or reported as blocking, and write a feature request when it is blocking. Use when L0 cannot express something, when reaching for a workaround for a language limitation, when tempted to modify the L0 toolchain, or when judging whether a limitation blocks the work.
---

# When L0 cannot express something

L0 is deliberately small. It grows only when real code cannot be written
without the addition, so hitting a wall is expected and is useful
information. Your job is to tell two cases apart:

- **a missing idiom**, which you work around and move on
- **a missing feature**, which you work around *and* write up as a request

Either way you keep working. The difference is whether a request comes out
of it.

**The L0 toolchain is read-only.** Do not edit the installed prelude, the
compiler, or anything under the install prefix, and do not vendor a patched
copy. The output of hitting a limit is working code plus, when warranted, a
document. Changing the language happens in the L0 repository, by a human who
has your request in hand.

## First, check it is really a language problem

Most walls are not. In the language's own history, three separate problems
looked like they needed a new primitive and none of them did.

**Is it about getting data in or out?** File names, several inputs,
arguments, exit status, progress reporting. L0's contract is bytes in, bytes
out, and the fix is almost always to put more structure on those bytes and
let the program on the other side deal with it. The L0 compiler reports
errors, names files in diagnostics, and distinguishes success from failure
through exactly this route, and needed no language change for any of them.
→ **Not a feature request.** Design a format.

**Is it a function you could just write?** There is no `map` or `filter`
because there are no function values, but a specialised version is usually
under ten lines. The prelude is small on purpose.
→ **Not a language request.** Write the function. If it is broadly useful,
request a *prelude* addition, which is far cheaper than changing the
language and is a different kind of ask.

## Then apply the cost test

Write the workaround first. A request must quote code that exists, not code
you imagine writing. If the workaround turns out to be fine, there is nothing
to report.

Then ask what the workaround costs:

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

**The program cannot be written at all → request.** Rare. Be certain, since
the two checks above rule out most apparent instances.

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

**Good.** "Encoding a tagged value as `(list int)` and decoding it by hand
appears in six places in `parser.l0`, and each new tag needs edits in the
encoder, the decoder, and every reader, with nothing checking they agree.
The workaround is in `parser.l0:40-120`. The smallest fix is parametric data
types with one type variable, no inference; it breaks the 'list is the only
parametric constructor' restriction."

The difference is not tone. It is that the good one contains evidence, names
a cost that grows, and proposes the least the language could change.
