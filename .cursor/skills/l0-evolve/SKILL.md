---
name: l0-evolve
description: Add or change a feature in the L0 language itself, keeping the spec, stage-0 interpreter, compiler, and tests in agreement. Covers the two-step rule for using a new feature inside the L0 compiler without breaking self-compilation. Use when changing spec/L0.md, adding a builtin or syntax form, or altering L0 semantics.
---

# Evolving L0

L0 grows only when the self-hosting goal demands it. A feature request with no
concrete blocker behind it is out of scope; the pressure of writing the compiler
is what justifies each addition.

Changing the language is not the same as changing a program in it. The spec, the
stage-0 interpreter, and eventually the L0 compiler all encode the same rules,
and they must agree or the bootstrap breaks in confusing ways.

## Order of work

**The spec changes first, always.** It is the only source of truth, and an
implementation that runs ahead of it produces code no future agent can justify.

```
1. spec/L0.md        state the new rule precisely
2. spec/changelog.md record what changed and WHY, with the blocker
3. stage0/l0i.c      reader, then checker, then evaluator
4. tests/            a passing case and a failing case for every new rule
5. compiler/*.l0     teach the L0 compiler to compile it (see two-step below)
6. tools/test.sh     green, then the bootstrap green
```

Skipping step 2 is the most common mistake and the most costly, because the
reason a feature exists is exactly what is unrecoverable later. The changelog is
the project's narrative; the spec only says what L0 *is*.

## The two-step rule

**To use a new feature inside the L0 compiler's own source, ship the ability to
compile it before you ship any use of it.** Two separate, individually
bootstrapped changes:

```
Step 1   compiler/*.l0 can COMPILE the feature, but uses none of it.
         Re-bootstrap. The fixpoint must hold.

Step 2   compiler/*.l0 now USES the feature in its own source.
         Re-bootstrap. The fixpoint must hold again.
```

Doing both at once produces a compiler whose source needs a feature that the
last working compiler cannot compile. Nothing in the chain can then build it,
and the only ways out are hand-editing generated IR or reverting. Neither is
pleasant.

The same rule applies to *removing* or changing the meaning of a feature, in
reverse: stop using it, bootstrap, then drop support, then bootstrap again.

## Keeping the implementations honest

Until the fixpoint is reached, L0 has two implementations: `stage0/l0i.c` and
`compiler/*.l0`. Every feature must land in both. This duplication is temporary
and is the reason stage 0 is deliberately minimal and disposable.

Once `seed/stage2.ll` is checked in and `stage0/` is deleted, there is exactly
one implementation, and language changes stop needing any host-language work at
all. Getting there is why the goal is worth pursuing.

While both exist and they disagree, **the spec decides which is wrong.** Do not
"fix" one to match the other without first confirming what the spec requires; if
the spec is silent, that is the actual bug, and the fix belongs in the spec.

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
