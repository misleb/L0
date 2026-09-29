# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: the memory-management and I/O goal is met by the language route
(changelog "The route to memory management and I/O"): streaming and file I/O,
arguments, reference counting, and guaranteed tail calls, and the gaps 0014
found in it are closed by 0018 to 0020. The arrays goal's release rule
(0023) and arrays (0024) are done, and 0028's programs with arrays chose
what follows: documentation that says what arrays cost, borrowed parameters,
nested update, and research into holding bytes one byte per byte.

## Language queue

Changes to the language, strictly in order. At most one is active.

1. [0030](0030-borrow-read-only-parameters.md) borrow a parameter the
   function only reads — queued, next
2. [0025](0025-nested-array-update.md) updating an array held inside another
   without copying it — queued, needs 0030

## Other open items

- [0026](0026-packed-bytes.md) research: how L0 holds bytes one byte per byte
  — proposed, next; earned by 0028

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
- [0010](0010-reference-counting.md) reclaim memory by reference counting —
  done, changelog "Memory is reclaimed by reference counting"
- [0013](0013-release-at-last-use.md) release a value at its last use —
  dropped; its blocker was the input list built before `main`, which no
  release rule can reduce
- [0011](0011-tail-calls.md) research: whether L0 guarantees tail calls —
  done, all of them, by musttail and padded arities
- [0015](0015-guarantee-tail-calls.md) guarantee every tail call — done,
  changelog "A tail call uses no stack"
- [0014](0014-programs-round-two.md) program: a second round of ordinary
  programs, to choose the next goal — done; nine programs, the ranking led
  to 0017 through 0021
- [0016](0016-linux-test-image.md) tooling: a local image for the Linux test
  runs — done, `tools/linux-test.sh`
- [0022](0022-library-reference.md) tooling: the standard library documents
  itself, and l0 init copies no reference — done, changelog "The standard
  library documents itself"
- [0017](0017-library-and-tool-fixes.md) tooling: library and tool fixes from
  0014 — done, changelog "Reading a line can report a failure, and no
  language change for it"
- [0018](0018-write-failures-reported.md) a program can learn that its writes
  failed — done, changelog "A program can learn that its writes failed"
- [0019](0019-append-and-rename.md) append to a file, and replace one whole —
  done, changelog "Appending to a file, and replacing one in a single step"
- [0020](0020-in-memory-handles.md) handles that read from and write to
  memory — done, changelog "Handles that read from and write to memory"
- [0021](0021-arrays-route.md) research: how L0 gets arrays, compact bytes,
  and in-place update — done; the release rule first (0023), then arrays
  (0024)
- [0023](0023-release-at-last-use.md) release a value at its last use — done,
  changelog "A value is released at its last use"
- [0024](0024-arrays.md) arrays — done, changelog "Arrays"
- [0029](0029-array-docs.md) say what arrays really cost — done, changelog
  "What updates an array in place, said correctly, and no language change
  for it"
- [0028](0028-programs-with-arrays.md) program: programs written with arrays
  — done; nine programs, all faster than Python, which chose 0029, 0030,
  0025, and 0026
- [0027](0027-faster-compiler.md) tooling: a faster compiler — done, changelog
  "Programs and the runtime are optimized together, and no language change
  for it"
