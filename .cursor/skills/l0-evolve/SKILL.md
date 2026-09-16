---
name: l0-evolve
description: Add or change a feature in the L0 language itself, keeping the spec, stage-0 interpreter, compiler, and tests in agreement. Covers the two-step rule for using a new feature inside the L0 compiler without breaking self-compilation. Use when changing spec/L0.md, adding a builtin or syntax form, or altering L0 semantics.
---

# Evolving L0

L0 grows only when real code cannot be written without the addition. Self
compilation supplied that pressure until it was reached; applications written
in L0 supply it now. A request with no concrete blocker behind it is out of
scope either way.

## Requests arriving from projects that use L0

Projects scaffolded by `l0 init` carry the `l0-limits` skill, which tells an
agent to work around a limitation and, when it is worth reporting, produce a
document under `l0/requests/`. Those documents are the input to this process.

A request is evidence, not a decision. Judge it against
[../../../lib/skills/l0-limits/SKILL.md](../../../lib/skills/l0-limits/SKILL.md),
which is the standard its author was held to, and send it back rather than
acting on it when:

- no workaround was actually written, so the cost is speculative
- the cost is constant per use site and has appeared in only one place
- it is really a host protocol question, which is what most requests about
  input, output, or file names turn out to be
- it is really an ordinary function, in which case the prelude may be the
  right home and no language change is needed

When a request is accepted, its "what could not be written" and "what the
workaround costs" sections are exactly what
[../../../spec/changelog.md](../../../spec/changelog.md) needs as the blocker
that motivated the change. Quote them rather than paraphrasing: the concrete
case is the part that becomes unrecoverable later.

Changing the language is not the same as changing a program in it. The spec, the
stage-0 interpreter, and eventually the L0 compiler all encode the same rules,
and they must agree or the bootstrap breaks in confusing ways.

## Order of work

**The spec changes first, always.** It is the only source of truth, and an
implementation that runs ahead of it produces code no future agent can justify.

```
1. spec/L0.md        state the new rule precisely
2. spec/changelog.md record what changed and WHY, with the blocker
3. compiler/*.l0     lexer, parser, checker, emitter (see two-step below)
4. tests/            a passing case and a failing case for every new rule
5. tools/test.sh     green, and tools/test.sh --compiled green
6. tools/bootstrap.sh --refresh-seed, and commit the seed
```

**Do not touch `stage0/l0i.c`.** It is frozen; see below.

Skipping step 2 is the most common mistake and the most costly, because the
reason a feature exists is exactly what is unrecoverable later. The changelog is
the project's narrative; the spec only says what L0 *is*.

## The two-step rule

**To use a new feature inside the L0 compiler's own source, ship the ability to
compile it before you ship any use of it.** Two separate, individually
bootstrapped changes:

```
Step 1    compiler/*.l0 can COMPILE the feature, but uses none of it.
          tools/bootstrap.sh          -- the fixpoint must hold

Step 1b   Install that compiler as the bootstrap seed, and commit it.
          tools/bootstrap.sh --refresh-seed

Step 2    compiler/*.l0 now USES the feature in its own source.
          tools/bootstrap.sh          -- the fixpoint must hold again
```

Doing both at once produces a compiler whose source needs a feature that the
last working compiler cannot compile. Nothing in the chain can then build it,
and the only ways out are hand-editing generated IR or reverting. Neither is
pleasant.

**Step 1b is not optional, and its position between the two steps is the whole
point.** The seed is a frozen compiler, so it can only compile features that
existed when it was cut. Refreshing after step 2 is too late: your working
tree keeps building because it already has a current compiler, while a fresh
clone becomes unbuildable because its only entry point never learned the
feature. Nothing you can run locally will reveal that, which is what makes the
ordering worth the ceremony.

`tools/bootstrap.sh` prints `SEED: STALE` when the seed no longer reproduces
itself from the current source. That is a warning, not an error, because a
stale seed still builds; it becomes a real problem only at step 2.

The same rule applies to *removing* or changing the meaning of a feature, in
reverse: stop using it, bootstrap, refresh the seed, then drop support, then
bootstrap again.

## Stage 0 is frozen

`stage0/l0i.c` is an interpreter for L0 as it stood when self-hosting was
reached. **Do not extend it for new language features.** It is no longer part
of the bootstrap, which runs entirely from `bootstrap/stage2.ll`, so adding a
feature to it buys nothing.

It is kept for one reason: it is an **independent implementation**, and
`tools/test.sh --compiled` judges the compiler against its behavior rather
than against expectations written by whoever wrote the compiler. That is the
strongest testing signal in this project, and it survives only as long as
stage 0 is not edited to agree with the compiler.

The consequence for a new feature is that programs using it cannot run under
stage 0. That is expected and handled: the compiled suite skips a program when
the compiler cannot build it, and a test using a new feature simply has no
interpreted counterpart. Coverage of the old language stays intact.

If the two disagree on something both support, **the spec decides which is
wrong.** Do not "fix" either to match the other without first confirming what
the spec requires; if the spec is silent, that is the actual bug, and the fix
belongs in the spec. Resist the reflex to edit stage 0, since that is how an
oracle quietly stops being independent.

## What makes a good feature

Favor features that make the checker *simpler* or catch more errors at compile
time, and be suspicious of ones that only save keystrokes. The existing
restrictions were chosen deliberately and are worth preserving unless a real
blocker overrides them:

- `match` patterns are one level deep with no wildcard, so adding a constructor
  becomes a compile error at every site that must handle it
- there is no type inference, so every expression's type is determined by itself
  and never by context
- `list` is the only parametric type constructor, so no unification is needed
  anywhere
- there are no function values, so name resolution is purely syntactic

Each of these keeps the self-hosted compiler small. Breaking one should buy
something substantial.

## Recording ambiguities

When implementing, you will find questions the spec does not answer. Do not
guess silently. Either settle it in the spec as part of this change, or record
the decision in `spec/changelog.md` under a "Resolved ambiguities" heading with
the reasoning, so it can be overruled later. The existing entries in
[spec/changelog.md](../../../spec/changelog.md) show the expected level of
detail: the question, the decision, and why it was made that way.

## Definition of done

- [ ] `spec/L0.md` states the rule, and nothing in it is now false
- [ ] `spec/changelog.md` says what changed and why
- [ ] `tools/test.sh` passes, including a new failing case per new error
- [ ] `tools/l0check` accepts what should be legal and rejects what should not
- [ ] the bootstrap fixpoint still holds, if a compiler exists yet
