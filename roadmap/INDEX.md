# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: memory management and I/O, by the language route: safe
facilities implemented in the runtime, I/O as effects in expression position,
and no raw memory in L0 code. See the changelog entry "The route to memory
management and I/O".

## Language queue

Changes to the language, strictly in order. At most one is active.

1. [0010](0010-reference-counting.md) reclaim memory by reference counting —
   queued, ready

## Other open items

- [0011](0011-tail-calls.md) research: whether L0 guarantees tail calls —
  proposed, can run at any time; interacts with 0010

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
- [0005](0005-memory-and-io-route.md) research: which route to memory
  management and I/O — done, the language route, changelog "The route to
  memory management and I/O"
- [0006](0006-ordinary-programs.md) program: write ordinary programs and
  record where L0 stops — done, seven limits and four spec findings
- [0007](0007-main-signature-check.md) checking enforces `main`'s signature —
  done, changelog "Checking a fragment still checks its main"
- [0008](0008-streaming-io.md) streaming standard input and output — done,
  changelog "Reading and writing as a program runs"
- [0009](0009-args-files-failure.md) arguments, files, and failure — done,
  changelog "Files, arguments, and names reserved for the standard library"
- [0012](0012-test-framework.md) tooling: a test framework in the standard
  library — done, changelog "A test framework, and no language change for it"
