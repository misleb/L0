# Skill note: limits-gating

Kind: skill
Status: draft
Project: hell0
Skill: l0-limits

## Which skill

`l0-limits`. The decision procedure has a false negative that is structural
rather than a matter of emphasis: one screen returns a terminal verdict on a
whole topic, and it runs before the test that would have caught this case, so
the strongest category in the skill is unreachable for anything shaped like
input or output.

The trigger was a one-line task — prompt for a name, print a greeting — that
L0 cannot perform. Following this skill as written, I shipped a program that
prints the question next to its own answer and reported it as done. The
limitation is real and is now filed as `0001-interactive-input`. The skill did
not merely fail to prompt me to file it; it told me not to.

## What the shipped skill said

The screen that decided it, in `## First, check it is really a language
problem`, which runs before the cost test:

```
**Is it about getting data in or out?** File names, several inputs,
arguments, exit status, progress reporting. L0's contract is bytes in, bytes
out, and the fix is almost always to put more structure on those bytes and
let the program on the other side deal with it. The L0 compiler reports
errors, names files in diagnostics, and distinguishes success from failure
through exactly this route, and needed no language change for any of them.
→ **Not a feature request.** Design a format.
```

Prompting is about getting data in, so this fires, and its verdict is
unqualified. The cost test never runs. That matters because the cost test is
where the correct answer lives:

```
**The program cannot be written at all → request.** Rare. Be certain, since
the two checks above rule out most apparent instances.
```

Unreachable here, and discouraging even when reached: it is fourth of five,
labelled rare, and its one instruction points back at the screens that already
excluded the case. "Be certain" has no test attached, so it reads as a reason
to keep looking for a workaround.

Three smaller things pushed the same way:

```
- **a missing idiom**, which you work around and move on
- **a missing feature**, which you work around *and* write up as a request

Either way you keep working.
```

Both cases begin with a workaround, so the vocabulary assumes one exists.
There is no case for "nothing I can write does this", and therefore no
instruction to tell the user.

```
Then ask what the workaround costs:
```

The cost test asks what a workaround costs, never whether it still does the
job. Changing the requirement is not among the costs it can express, so a
workaround that silently narrows the task scores as cheap. Mine scored as
constant-per-use-site, which is exactly the verdict a few lines of prompt text
deserves if you do not ask whether the prompt prompts.

```
**Bad.** "L0 needs file I/O to read a config file." This is the data-in
question above. The host can pass the config on stdin in a bundle.
```

The only worked I/O example is a refusal, with no counterpart going the other
way, so the pattern available to match against is "input topic, decline".

## What this project wrote instead

Four changes. The first is the load-bearing one; the others stop the same
reasoning being reachable by another route.

**1. A gate before the topic screens, and above them in the file.** The
screens sort by subject, and the thing they must not be allowed to sort is a
task that cannot be done at all.

```
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
have the last entry in the cost test below, you say so in your reply instead
of reporting the work as done, and **the topic screens in the next section do
not apply**: they sort limitations by subject, and a task you cannot perform
is not a subject.

This is the failure the skill exists to prevent, and it is worse than a
wrongly filed request. A bad request costs a maintainer a few minutes and
gets declined. A program that quietly does something adjacent to what was
asked costs whoever believed it, and there is nothing in a passing test suite
to catch it, because the tests were written from the same misreading.
```

**2. The I/O screen made conditional, with the exception named.** The
condition is the one that actually distinguishes the cases, and the compiler
evidence is scoped to what it can support.

```
**Is it about getting data in or out, and does all of that data exist before
the program starts?** File names, several inputs, arguments, exit status.
[...unchanged...]
→ **Not a feature request.** Design a format.

**The exception is ordering.** The host reads stdin to end of file, evaluates
`main`, and then writes the result, so every byte the program reads was
chosen before it emitted any. If what the program must read depends on the
user having seen what it wrote — a prompt, a confirmation, a menu, a retry on
bad input, anything with a turn in it — then no format fixes it. Structure
says what bytes mean; it cannot say whose turn it is. The compiler, which is
all of the evidence for the paragraph above, is a batch program that never
wanted a turn, so it is evidence about content and silent about ordering.
→ **Candidate request.** Name the two events that need reordering.

The question to ask is not "is this about input?" but "does the input depend
on my output?". Answering the first one and stopping is how a task gets
quietly redefined.
```

Progress reporting moved out of the screen's list, since it is neither: it
needs early output but no turn, and the note says to propose it separately
rather than bundled with a prompt.

**3. The impossibility cost given a test instead of a warning.**

```
**The program cannot be written at all → request, and say so out loud.**
Uncommon, and the checks above do rule out most apparent instances, so the
bar is a demonstration rather than a feeling. Name the requirement, name the
two things that cannot both hold, and measure it. "I could not find a way" is
not a demonstration. "The host finishes reading stdin before evaluation
begins, and here is the timestamped run showing the question printed after
the answer was consumed" is.

Once you have that, file it. Do not go back around the screens looking for the
verdict you expected; a demonstrated impossibility does not become more
certain by sitting on it, and being told the limitation was acceptable is
cheap compared to shipping a program that does something else. This is also
the one cost the user has to hear about directly, because it is the one where
the thing they asked for is not what they are getting.
```

**4. A third case at the top, and a matched pair of examples.** The case list
no longer presumes a workaround exists:

```
- **a missing capability**, where nothing you can write does what was asked:
  you write the request, ship the closest honest thing, and say plainly that
  it is not what was asked for
```

and the config-file refusal now has a counterpart on the same topic with the
opposite verdict, closing with the distinction rather than the topic:

```
Those two are the same topic and opposite verdicts. The config file exists
before the program starts; the name does not exist until the user has read
something. Sorting on the topic gets the second one wrong every time.
```

## The code that proved it better

The old text produced `src/greeting.l0` as originally shipped: legal,
type-checked, twenty passing assertions, and not a prompt.

```
(def greet ((input (list int))) (list int)
  (let a (push (prompt) (nil int))
    (rev (push (greeting (name_from input)) a))))
```

The new gate's first question — would someone watching agree it asked? —
fails immediately, and measurably. With the answer supplied at once and end of
file held off three seconds:

```
$ { printf 'Ada\n'; sleep 3; } | ./build/hell0 | while IFS= read -r l; do
      printf 't=%ss  %s\n' "$SECONDS" "$l"; done
t=4s  What is your name? Hell0, Ada!
```

The question arrives after the answer was read, always. Worth noting what did
*not* catch this: `l0 check` passed, and the test suite passed with twenty
assertions, including four that asserted on the prompt. The assertions
encoded the same misreading as the code, which is why the check has to be
against the requirement and not against the program.

Under the new text the same limitation routes to a request
(`0001-interactive-input`), and the project ships the honest version: a
wrapper that asks, and an L0 program that answers one turn of it, which needed
a directive vocabulary and a three-case request type to be callable twice.

```
(data Request
  (AskName)
  (GreetName (list int))
  (Batch (list int)))
```

That machinery is the evidence in the request, and it only exists because the
gate now forces the question to be asked before the cost is weighed.

## What is general

The false negative, not the feature. Any decision procedure that screens by
topic before testing severity will mis-sort the severe cases whose topic looks
routine, and "input and output" is the topic most likely to hide one, because
L0's bytes-in-bytes-out contract makes almost everything about I/O genuinely
not a language problem. That correct general rule is what makes the exception
invisible.

Three parts of this belong in any project:

- **Check the requirement survived before classifying the limitation.** Cost
  tests presume a workaround that works and only price it. Nothing else in the
  skill notices a workaround that changed the task.
- **Scope the evidence for a screen to what it covers.** The compiler is the
  authority for every "this is not a language problem" claim in the skill, and
  it is a batch program, so it cannot speak to interaction. Screens should say
  what their evidence does not cover, or they read as settled where they are
  merely untested.
- **Pair a refusing example with an accepting one on the same topic.** A lone
  bad example on a topic teaches the topic, not the distinction.

One thing deliberately not proposed: a general instruction to file requests
more readily. The screens exist because most walls are not language problems,
that is true, and loosening them everywhere would trade this false negative for
a stream of false positives and make the skill's advice worth less. The fix is
to remove the specific gate that mis-routes correctness failures and to give
the impossibility case a demonstration it can meet, so that what increases is
requests that carry evidence rather than requests in general.

---

## Triage

Accepted in substance, and merged into `lib/skills/l0-limits/SKILL.md`. The
diagnosis is right and is confirmed by the spec rather than only by the
transcript: section 9 of `spec/L0.md` defines the host as reading stdin to end
of file, then evaluating `(main input)`, then writing the result. The skill's
I/O screen was stating a consequence of step 1 as if it covered all three
steps, so a task blocked on the ordering between them matched a screen that
had no evidence about ordering.

Merged, adapting the note's wording where the surrounding text required it:

- the gate, as `## First, check the task survived`, above the screens; the
  following section is renamed `## Next, ...` so the order reads
  First / Next / Then
- the I/O screen made conditional on the data existing before the program
  starts, with the ordering exception and the scoping of the compiler
  evidence
- the impossibility entry rewritten around a demonstration, and **moved to
  the front of the cost test**, which the note did not ask for: the gate now
  routes directly to that entry, and a reader arriving there should not have
  to scan past three cheaper verdicts first
- the third case, *a missing capability*, at the top of the skill
- an accepting I/O example paired with the config-file refusal, and the
  closing distinction. The note quoted only the closing paragraph, so the
  example itself was written here from the note's evidence

Two extensions beyond the note:

- Progress reporting was dropped from the screen's list, as the note asked,
  but instead of being left for a separate proposal it is named in the
  exception as the same ordering fact seen from the output side. The spec
  backs this directly — nothing is written until `main` returns — so it is a
  demonstrated case, not a speculative one, and leaving it unmentioned would
  have deleted a listed item with no replacement.
- `lib/AGENTS.md` carries the same screen in condensed form and is also
  copied by `l0 init`. Fixing only the skill would have left an always-on
  file asserting the unqualified version, which outranks a skill. It now
  carries the ordering exception and the requirement-survived check in two
  sentences.

Not merged, as project-specific:

- `src/greeting.l0`, `./build/hell0`, the timed transcript, and the
  cross-reference to `0001-interactive-input`. These are what made the note
  judgeable and they stay here as the evidence for the change; the skill gets
  the rule, not the run.
- the `Request` / `AskName` / `GreetName` / `Batch` directive vocabulary and
  the asking-wrapper architecture. That is one design for one project's
  shape. It is the right evidence for the language request it accompanies,
  but as skill text it would teach a specific protocol as the answer to
  interaction, and the skill's job is to get the limitation reported, not to
  prescribe the workaround.

The note's own restraint is worth recording: it explicitly declined to
propose a general instruction to file requests more readily, on the grounds
that loosening the screens everywhere would trade this false negative for a
stream of false positives. That is correct, and it is why the merge is a gate
plus one named exception rather than a softening of the screens.
