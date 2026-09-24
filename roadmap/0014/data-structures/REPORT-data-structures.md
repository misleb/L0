# Data structures and algorithms: what three programs hit

Three programs, each in its own directory with tests and a README:

| program | status | tests | headline measurement |
| --- | --- | --- | --- |
| [json](json/README.md) | done | 27 pass | 11.5 MB in 1.9 s, byte-identical to Python's json.tool; 873 MB peak |
| [kvstore](kvstore/README.md) | done, workaround | 19 pass | 100k keys: one file 160 ms/set, 256 buckets 3 ms/set |
| [paths](paths/README.md) | done, workaround | 17 pass | 10k nodes, 100k edges: 32 ms/query (CPython 10.7 ms) |

Every test also passes under `L0_RC_CHECK` with no runtime report, checked
with `rc_check_tests.sh`, because `l0 test` hides the report (see below).
Every test file also caught a deliberate mutation of its code.

## The limits, ranked by what they cost

A smallest program with its checker output or measurement is in
`limits/NN-*.l0`, and the code wanted in its place is in
`hypothetical/NN-*.l0`.

1. **02: no append, seek, or rename** (kvstore). This was impossible to work
   around fully: crash-safe updates cannot be written at all, since
   `open_write` empties the file first and nothing can replace a file whole.
   Every write costs the whole file: 1.7 µs per stored key, 160 ms per set at
   100k keys, about 2.4 hours to load 100k keys through `kv set`. The
   workaround (256 bucket files) is 20 times faster but still linear. It
   leaves files that L0 can neither list nor delete, and it is no safer.
2. **01: no array or other O(1) indexed table** (paths). O(1) indexing is
   impossible; the workaround is a persistent trie, about 75 lines across its
   copies. A read costs 140 ns and an update 470 ns, where an array load
   would be a few ns. Dijkstra is 3 times slower than CPython, with 61% of
   the time in reference-count increments and decrements while walking trie
   nodes that are only being read.
3. **03: no type parameters** (all three). The standard library cannot
   provide a map, set, heap, Option, or Result, since each has to be written
   once per element type, so every program rewrites them. About 100 of 1,607
   lines are copies: the trie three times, `rev` three times, and ten
   single-use result or state types.
4. **04: bytes are cons cells, 24 bytes each** (json). The 24x overhead is
   measured at 1, 10, and 100 MB; json peaks at 76 times its input. Nothing
   is blocked at test sizes, but a 100 MB document needs about 7.6 GB.
5. **07: `lib/io.l0` drops failure detail** (kvstore). `IoFailed` is words
   only, so kv compares against the text `"no such file"`. `file_read_line`
   reports a failed read as the end of the file, which would make kv silently
   drop entries on rewrite. The workaround is about 40 lines of kv's own line
   reader.
6. **06: no wildcard arm** (json tests). Sidestepped: equality over 6
   constructors is 36 arms, so the round-trip test compares rendered text.
7. **05: a whole-input `main` always exits 0** (json). The workaround is a
   streaming `main` and a 4-line `read_stdin`.

Not worth a limit, but noticed: there are no bitwise operations, so the trie
branches on `mod 2` and `div 2` and hashing uses `mod`, both cheap. There are
no function values; kv's `run` takes an int instead of a function. There is
no clock, so every timing was taken from outside.

## Mistakes made or nearly made

None of the L0 was rejected by the checker: every file type checked the
first time it was run, except for one name collision (below). The syntax
warnings in the l0-code skill were followed throughout. In particular, every
guard on `head` is a nested `if`, never `and` or `or`. The mistakes were all
in things the checker cannot see:

- **A doubled colon in json's error prefix**, `stdin:2:5::`. Caught by
  running the program by hand; the tests would have caught it too.
- **The deep-nesting test**, twice. I wrote a wrong closed form for the
  rendered length, and I did not see that indented output of d nested arrays
  is quadratic in d. The first version, at 20,000 levels, would have rendered
  about 800 MB, some 19 GB of cons cells. Caught by re-deriving the formula
  before running it; no tool would have caught it except by exhausting
  memory.
- **Calling the prelude's `length` on a whole input.** It is not tail
  recursive, so 10 million elements cost 320 MB of stack. Found only while
  measuring limit 04, whose numbers came out twice too high.
- **`hex_digit` collided with `lib/test.l0`** under `tools/l0check`, which
  cannot put the test library in the prelude group. `l0 test` would have
  accepted it as shadowing. I renamed kv's `fail` to `kv_fail` for the same
  reason before it came up.
- **Timings taken with `L0_RC_CHECK=1` still exported** from a previous
  command. Checking disables block reuse, so those timings were wrong.
  Noticed and re-measured.
- **Nearly trusting `L0_RC_CHECK` under `l0 test`.** The leak report goes to
  standard error and does not change the exit status, and `l0 test` shows
  standard error only for failing tests. So a leak in a passing test is
  invisible. `rc_check_tests.sh` builds the same generated `main` and reads
  standard error itself. It found no leaks in any of the 63 tests.

## Spec and skill problems

- **The shipped skill's paths are for an `l0 init` project**: `l0/L0.md`,
  `l0 check`, `l0/examples.l0`. In this repository those are `spec/L0.md`,
  `tools/l0check` or `tools/l0 check`, and `lib/`. The difference is
  harmless once noticed, but a first read follows paths that do not exist.
- **No checker invocation checks a test file the way `l0 test` compiles
  it.**
  - `tools/l0check` links no library, so the library files have to be passed
    in by hand. They then land in the program group, and spec 7.1's
    shadowing becomes "function hex_digit is already defined".
  - `tools/l0 check` groups correctly but cannot include `lib/test.l0`.
- **`L0_RC_CHECK` reports go unseen under `l0 test`**, as above. Either a
  nonzero exit status on a report, or `l0 test` showing reports for passing
  tests, would fix it.
- **The prelude contradicts the skill's advice.**
  - `length`, `append`, and `args_from` are not tail recursive, while the
    skill says to write loops as tail calls; `length` is the one reached for
    most often.
  - `file_read_line` treats a failed read as the end of the file, while the
    skill says to "test for -1 and for other negatives separately".
- **The skill says "report failure by returning a nonzero exit status from
  main"**, which only the streaming `main` can do (limit 05). The sentence
  sits in the files section and reads as general.
- **Spec 10.3 says the runtime "is LLVM IR, linked into every compiled
  program"**, but `tools/l0` links a compiled object. So `l0_data_get`,
  `l0_data_tag`, `l0_div`, and `l0_mod` are real calls that are never
  inlined: 12% of a Dijkstra query goes to `l0_data_get` alone.
- **The spec does not say how deep non-tail recursion may go.** In practice
  100,000 levels of JSON nesting and 10 million frames of `length` both
  worked. The skill says only "very deep".
