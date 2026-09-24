# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: memory management and I/O. The C is gone from compiled
programs, and C remains only in `stage0/`. The goal starts by choosing a
route: 0005, with 0006 as its evidence.

## Language queue

Changes to the language, strictly in order. At most one is active.

Empty.

## Other open items

- [0005](0005-memory-and-io-route.md) research: which route to memory
  management and I/O — active; questions 1, 2, 3, and 5 answered
  provisionally, question 4 and the recommendation wait on 0006, and the
  answer needs the user's agreement
- [0006](0006-ordinary-programs.md) program: write ordinary programs and
  record where L0 stops — active, running as a worker

## Done and dropped

- [0001](0001-shed-c-runtime-plan.md) research: how to shed the C runtime —
  done
- [0002](0002-runtime-in-l0.md) program: write the runtime in L0 — done, ten
  limits recorded
- [0003](0003-ir-runtime.md) link compiled programs against an IR runtime
  instead of C — done, changelog "The runtime is LLVM IR, and stack exhaustion
  is checked rather than caught"
- [0004](0004-retire-c-runtime.md) tooling: retire the C runtime files — done;
  C remains only in `stage0/`
