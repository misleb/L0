# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: shedding the C runtime, so that no C source goes into a compiled
program. libc stays as the interface to the operating system; see the
changelog entry "A new goal".

## Language queue

Changes to the language, strictly in order. At most one is active.

1. [0003](0003-ir-runtime.md) link compiled programs against an IR runtime
   instead of C — queued, ready

## Other open items

- [0001](0001-shed-c-runtime-plan.md) research: how to shed the C runtime —
  active; questions 2–5 answered, question 1's long-term half waits on 0002
- [0002](0002-runtime-in-l0.md) program: write the runtime in L0 — active,
  running alongside 0001
- [0004](0004-retire-c-runtime.md) tooling: retire the C runtime files —
  proposed, needs 0003

## Done and dropped

Nothing yet.
