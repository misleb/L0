---
name: l0-roadmap
description: Organize, track, and coordinate L0 development locally, using the tracked roadmap/ directory and local subagents. Covers picking the next work item, keeping language changes in one serial queue, running research and program-writing in parallel in git worktrees, and turning limits that workers hit into language changes. Use when planning or starting L0 work, asking what to do next, updating status, breaking a goal such as memory management or I/O into steps, or delegating L0 work to subagents.
---

# Coordinating L0 development

Everything runs locally. Plans and status live in `roadmap/`, tracked in git,
so every agent sees the same state and plans have history. Work is done by you
or by local subagents; nothing depends on a cloud service.

## What roadmap/ holds, and what it must not

`roadmap/` holds plans, status, and research findings. It must never be where
knowledge about L0 lives. The experiment is whether an agent can go far with
the spec, examples, and skills alone, so:

- what L0 is goes in `spec/L0.md`
- why L0 is that way goes in `spec/changelog.md`
- how to write or change L0 goes in a skill, `lib/examples.l0`, or `AGENTS.md`

If an agent would need to read `roadmap/` to write correct L0, something is in
the wrong place. When an item is done, its lasting reasoning moves to the
changelog and the item keeps only a pointer to it.

## Layout

```
roadmap/
  INDEX.md            the language queue and every open item
  0001-some-slug.md   one file per item, numbered in creation order
  0001/               optional: prototypes and scripts the item produced
```

An item's directory holds evidence that must outlive `build/`, such as a
prototype a later item starts from. It is deleted when the item that uses it
lands, since by then the real thing exists.

Create it from the templates below the first time it is needed. Numbers are
never reused. A dropped item stays, with the reason, for the same reason the
changelog keeps rejected ideas.

`INDEX.md`:

```markdown
# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

## Language queue

Changes to the language, strictly in order. At most one is active.

1. [0003](0003-slug.md) title — active
2. [0005](0005-slug.md) title — queued, needs 0004

## Other open items

- [0004](0004-slug.md) research: title — active
- [0006](0006-slug.md) program: title — proposed

## Done and dropped

- [0001](0001-slug.md) title — done, changelog "Entry title"
```

Item file:

```markdown
# 0003: title

Kind: language | research | program | tooling
Status: proposed | queued | active | done | dropped
Needs: 0002, 0004        (or: nothing)

## Why

The code this makes possible or harder to get wrong. For a language item,
the smallest L0 program that cannot be written today, quoted, with the
checker's output.

## Done when

Concrete and checkable. For a language item, the checklist in the
l0-bootstrap skill plus whatever this item adds.

## Log

- YYYY-MM-DD: what happened, what was decided, what is next
```

The four kinds:

- **language** changes `spec/L0.md`, the compiler, the runtime, or the prelude.
  It goes in the queue.
- **research** answers a question with a written finding in its Log and changes
  nothing else, for example comparing memory-management designs against spec
  section 10.3.
- **program** writes real L0 to find out where it breaks. Its product is the
  list of limits hit, each with the smallest program that shows it.
- **tooling** covers scripts and docs that are not the language.

## Picking the next thing

1. Read `roadmap/INDEX.md`. If an item is active, continue it before starting
   anything new.
2. If no language item is active, take the first queued one whose `Needs` are
   done and mark it active. A language item with no code in its Why section is
   not ready; open a program or research item that will produce that code.
3. While a language item is active, research and program items may run
   alongside it, within the limits under "Parallel work".
4. When the queue is empty, go back to the goals: take the next gap (memory
   management, then I/O, then dropping the C runtime) and open the research or
   program item that would produce its first language item.

Break a goal down until each language item is one bootstrapped change. When the
compiler's own source is going to use the new feature, that is two language
items, support and then use, per the two-step rule in `l0-bootstrap`, with the
seed refresh between them.

## Language items are serial

Only one language item is active at a time, and it is done in the main working
tree, never by a parallel worker. The spec, the compiler sources, the prelude,
and the runtime are single points of contention, and `bootstrap/stage2.ll` is
generated IR that cannot be merged: when two branches both refresh it, one of
them is redone from scratch.

Follow the order of work in the `l0-bootstrap` skill for every language item.
Update the item file and `INDEX.md` in the same change as the work itself.

Committing is the user's call. Where work must be committed before the next
step can start, such as the seed refresh between the two halves of the
two-step rule, stop and ask.

## Parallel work

Research and program items can run in parallel through the Task tool:

- `explore` or `generalPurpose` for read-only research that returns a finding
- `best-of-n-runner` for anything that writes files. Each runs in its own git
  worktree and branch, so parallel workers cannot collide.

Launch independent workers in a single message with `run_in_background: true`.

A subagent sees none of your conversation, so its prompt must stand alone. It
must include:

- the path of its item file, and an instruction to read `AGENTS.md` and the
  `l0-code` skill before writing any L0
- that it must not edit `spec/`, `compiler/`, `runtime/`, `bootstrap/`,
  `stage0/`, `lib/prelude.l0`, or `roadmap/`, which the coordinator owns
- in a worktree, that `build/` starts empty, so it runs `tools/build.sh`
  before `tools/l0check` or any test
- what to return, below

**Tell program workers to report limits, not route around them.** A worker that
cannot change the language will otherwise work around the limit and ship, and
the pressure that should have shaped L0 is lost; that is what sank the external
request loop. Give it this instruction: when L0 cannot express something, stop
that part, write the smallest program that shows the limit, confirm with
`tools/l0check` that the failure is real, and report it. Write a workaround only
if the item asks for one, and name it as a workaround.

Ask every worker to return:

- what it did, and the paths of the files it wrote in its worktree
- for a program item, each limit hit: the code that could not be written, what
  was tried, and the checker's output
- anything in the spec it found ambiguous or wrong

## Bringing results back

Read each report, and do not take it at face value. Re-run `tools/l0check` on a
claimed limit in the main tree before acting on it.

- Record the finding in the item's Log and update or close the item.
- Each confirmed limit becomes a language item in the queue, with the worker's
  smallest program as its Why. The answer to a limit is to change L0; the queue
  decides only when.
- A spec ambiguity is settled in the spec, as its own small language item.
- Code worth keeping, such as a program that should become a test or an
  example, is brought into the main tree as part of an item. Merging a worker's
  branch, or committing, needs the user's go-ahead.

## Ending a session

Leave `INDEX.md` accurate, and give every active item a Log line saying what
comes next, so the next agent can start from the index alone.
