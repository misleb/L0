# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: the memory-management and I/O goal is met by the language route
(changelog "The route to memory management and I/O"): streaming and file I/O,
arguments, reference counting, and guaranteed tail calls, and the gaps 0014
found in it are closed by 0018 to 0020. The arrays goal's release rule
(0023) and arrays (0024) are done, and 0028's programs with arrays chose
what followed them (0029, 0030, 0025, 0026). 0026 found that holding text
one byte per byte needs a packed type, and that adding builtins must first
stop breaking programs; 0031 and 0032 did both, and 0033 put bytes to use in
the library and the text programs. Type parameters came next (0035): data
types take them (0036), a program's types shadow the library's (0037), the
library declares Option and Result (0039), and functions take them (0038),
so the library's list helpers now take every element type (0040). 0041
found that a generic function could not compare its elements, and `eq` now
compares two values of any type (0042), which the library and the suite
now use (0043). The compiler and the prelude could use neither, since stage
0 still ran their source; 0044 found that only the tools required it, and
the tools no longer do (0045). The prelude has taken back the generic
definitions, which the compiler now calls (0046), and the compiler is
written with type parameters and `eq` throughout (0047). Left from 0041's
candidates, `compare` and function values wait for a program that needs
them. 0049 found that a program can tell I/O failures apart only by their
words or codes, which the checker cannot see, and opening a file now says
which failure it was as a case typed per kind of open (0050); renames,
removals, flushes, and closes now do too (0062), and reads keep codes. 0051
found that no map can be written once for every key type, since nothing
can hash a value of a type parameter. `hash` now gives any value a
specified integer (0052), and the prelude has a `(Map K V)` for every key
and value type (0053), which the compiler's pad table and the suite's graph
now use (0054). A persistent map and an ordered one wait for code that
needs them. Everything through 0054 has passed on Linux, 0056 needed no
run, and 0057, 0058, 0061, and 0062 have passed on arm64. 0055's third
round of programs found a copying bug in the map (0056) and three places
the runtime broke section 6.3 (0057), both fixed, and earned bitwise
operations (0058), which make its hash program 4.2 times faster, a delete
(0061), and typed failures beyond opening (0062), all done. Waiting on
research: ordering any type (0059), and bounded reads with updatable bytes
(0060).

## Language queue

Changes to the language, strictly in order. At most one is active.

Empty.

## Other open items

- [0059](0059-compare-or-function-values.md) research: ordering a value of
  any type, by `compare` or by function values — proposed
- [0060](0060-bounded-reads-and-updatable-bytes.md) research: reading at
  most n bytes, and bytes that update in place — proposed

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
- [0025](0025-nested-array-update.md) updating an array held inside another
  without copying it — done, changelog "A row of an array of rows updates in
  place, written the natural way"; Linux run with 0044
- [0030](0030-borrow-read-only-parameters.md) read-only parameters — done,
  changelog "Read-only parameters"; Linux run with 0044
- [0029](0029-array-docs.md) say what arrays really cost — done, changelog
  "What updates an array in place, said correctly, and no language change
  for it"
- [0028](0028-programs-with-arrays.md) program: programs written with arrays
  — done; nine programs, all faster than Python, which chose 0029, 0030,
  0025, and 0026
- [0027](0027-faster-compiler.md) tooling: a faster compiler — done, changelog
  "Programs and the runtime are optimized together, and no language change
  for it"
- [0026](0026-packed-bytes.md) research: how L0 holds bytes one byte per byte
  — done; a packed type (0032), after 0031, then 0033
- [0031](0031-builtins-do-not-take-over.md) a new builtin does not take over
  a program's function — done, changelog "A new builtin does not take over a
  program's function"; Linux run with 0044
- [0032](0032-bytes.md) bytes held one byte per byte — done, changelog
  "Bytes, held one byte per byte"; Linux run with 0044
- [0033](0033-bytes-library-and-programs.md) tooling: the library reads into
  bytes, and the text programs use it — done, changelog "The library reads a
  whole input into bytes, and no language change for it"; Linux run with
  0044
- [0034](0034-clock.md) a clock — done, changelog "A clock"; Linux run with
  0044
- [0035](0035-type-parameters.md) research: how L0 gets type parameters —
  done; parametric data (0036), then library type names (0037), then
  parametric functions (0038)
- [0036](0036-parametric-data.md) data types take type parameters — done,
  changelog "Data types take type parameters"; Linux run with 0044
- [0037](0037-library-type-names.md) a program's types do not collide with
  the library's — done, changelog "A program's types shadow the library's,
  and Io names are no longer reserved"; Linux run with 0044
- [0039](0039-library-option-result.md) tooling: the library declares
  Option and Result — done, changelog "The library declares Option and
  Result, and no language change for it"
- [0038](0038-parametric-functions.md) functions take type parameters —
  done, changelog "Functions take type parameters"
- [0040](0040-library-list-helpers.md) the library's list helpers work at
  every element type — done, changelog "The library's list helpers take
  every element type, and no language change for it"
- [0041](0041-comparing-any-type.md) research: how L0 compares values of any
  type — done; `eq` on any type first (0042)
- [0042](0042-eq-any-type.md) `eq` compares two values of any type — done,
  changelog "`eq` compares two values of any type"
- [0043](0043-library-onto-eq.md) the library and the suite's programs use
  `eq` — done, changelog "The library compares with eq, and no language
  change for it"
- [0044](0044-compiler-free-of-stage0.md) research: how the compiler and the
  prelude stop being run by stage 0 — done; the tools first (0045), then
  0046 and 0047
- [0045](0045-tools-without-stage0.md) tooling: the tools stop running the
  compiler under stage 0 — done, changelog "The compiler's source is no
  longer run by stage 0, and no language change for it"; Linux run with
  0054, after a fix
- [0046](0046-prelude-generics.md) the prelude takes back the generic
  definitions — done, changelog "The prelude takes back the generic
  definitions, and no language change for it"
- [0047](0047-compiler-uses-generics.md) the compiler uses type parameters
  and eq — done, changelog "The compiler is written with type parameters
  and eq, and no language change for it"
- [0048](0048-examples-current.md) tooling: the examples show what L0 has
  gained since they were written — done
- [0049](0049-io-failure-names.md) research: whether I/O failures should be
  named cases rather than codes — done; typed failures for opening (0050)
  first
- [0050](0050-open-failures-named.md) tooling: opening a file says which
  failure it was, as a case the checker knows — done, changelog "Opening a
  file says which failure it was, and no language change for it"
- [0051](0051-hash-and-map.md) research: how L0 gets a hash and a map —
  done; `hash` (0052), then a library map (0053), then its users (0054)
- [0052](0052-hash-builtin.md) `hash` gives a value of any type a specified
  integer — done, changelog "`hash` gives a value of any type a specified
  integer"; Linux run with 0054
- [0053](0053-library-map.md) the prelude has a map for every key and value
  type — done, changelog "The prelude has a map for every key and value
  type"
- [0054](0054-map-users.md) tooling: the compiler and the suite use the
  library's map — done, changelog "The compiler and the suite keep their
  tables in the library's map, and no language change for it"
- [0055](0055-programs-round-three.md) program: a third round of ordinary
  programs — done; nine programs, which chose 0056 to 0063
- [0056](0056-map-remove-in-place.md) `map_remove` updates in place — done,
  changelog "Removing a key from a map no longer copies it, and no language
  change for it"
- [0057](0057-io-keeps-section-6-3.md) the runtime keeps section 6.3's
  promises — done, changelog "A broken pipe is a write failure, a closed
  standard handle is open on nothing, and -3 means nothing is there"; passed
  on Linux arm64
- [0058](0058-bitwise-operations.md) bitwise operations — done, changelog
  "Bitwise operations"; passed on Linux arm64
- [0061](0061-delete-a-file.md) delete a file — done, changelog "Deleting a
  file"; passed on Linux arm64
- [0062](0062-typed-rename-flush-close.md) rename, remove, flush, and close
  say which failure it was — done, changelog "Renaming, removing, flushing,
  and closing say which failure it was"; passed on Linux arm64
- [0063](0063-docs-and-tools-from-0055.md) tooling: the doc and tool
  findings of 0055 — done, changelog "A declaration that does not parse is
  reported once, and no language change for it"
