# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: the C is gone from compiled programs. What remains of that
milestone is 0004's cleanup. The next goal is memory management and I/O, and
the first decision in it is open; see "Next" below.

## Language queue

Changes to the language, strictly in order. At most one is active.

Empty.

## Other open items

- [0004](0004-retire-c-runtime.md) tooling: retire the C runtime files —
  proposed, ready

## Next

0002's limits are the complete list of what L0 would need in order to write
its own runtime. Now that the runtime is IR, that is one route to the
memory-management and I/O goals, not the only one. The research item that
starts the goal has to be opened with the route chosen, or with choosing it
as its question.

## Done and dropped

- [0001](0001-shed-c-runtime-plan.md) research: how to shed the C runtime —
  done
- [0002](0002-runtime-in-l0.md) program: write the runtime in L0 — done, ten
  limits recorded
- [0003](0003-ir-runtime.md) link compiled programs against an IR runtime
  instead of C — done, changelog "The runtime is LLVM IR, and stack exhaustion
  is checked rather than caught"
