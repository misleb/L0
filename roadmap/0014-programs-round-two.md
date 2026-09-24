# 0014: A second round of ordinary programs, to choose the next goal

Kind: program
Status: done
Needs: nothing

## Why

The memory-management and I/O goal is met. The next goal was left to the
evidence at the user's choice, over picking parametric types, data
structures, or function values directly. [0006](0006-ordinary-programs.md)
is the model: write real programs, record where L0 stops with the smallest
failing program, and let that choose. This round has what 0006 lacked:
streaming and file I/O, arguments, reclaimed memory, and `l0 test`.

## The task

Three `best-of-n-runner` workers, in parallel, three programs each:

- **text tools:** a word-frequency counter sorted by count, a CSV column
  extractor with quoted fields, an interactive calculator with precedence
- **data structures and algorithms:** a JSON validator and pretty-printer, a
  persistent key-value store usable at 100,000 keys, shortest paths on a
  graph of 10,000 nodes and 100,000 edges
- **bytes and encodings:** a streaming base64 encoder and decoder, a line diff
  by longest common subsequence, a grep with `.`, `*`, `^`, and `$`

Each writes unit tests with `l0 test`, runs under `L0_RC_CHECK`, measures
time and memory at the stated sizes, records every limit with its smallest
program and the code it would have written, may work around a limit only if
it names the workaround and its cost, and ranks the limits by what they cost.

## Done when

- every limit reported has been re-checked in the main tree and logged here
- the rankings are combined into a proposal for the next goal, which the user
  agrees to

## Log

- 2026-09-24: opened; the three workers launched.
- 2026-09-24: **all three reported**, and all nine programs work. Their
  programs, tests, limit programs, hypotheticals, and reports are copied into
  [0014/](0014/): `text-tools/README.md`, `data-structures/REPORT-data-structures.md`,
  and `bytes-encodings/README.md` are the write-ups. None changed anything
  outside `programs/`. Every file they wrote type checked the first time, and
  `L0_RC_CHECK` never fired; `l0 test` caught the logic bugs.

  *Re-checked in the main tree:*
  - writes to a closed standard output are lost and the program exits 0
    (`bytes-encodings/limits/01`); `close` refuses handles 0 to 2, so nothing
    can report it
  - a histogram of 1 MB as a list of 256 counts takes 1.48 s, and as a depth-8
    tree 0.33 s; they agree (`text-tools/limits/01`)
  - appending one line to a 200,000-line file reads and rewrites all of it,
    since `open_write` empties and there is no append or rename
    (`data-structures/limits/02`)
  - holding 10 MB of input as a list peaks at 242 MB
    (`data-structures/limits/04`)
  - `read_line` and `file_read_line` in `lib/io.l0` treat every negative
    result as end of input, so a failed read looks like a short file
  - `tools/l0` never looks at `L0_RC_CHECK`, and the runtime reports live
    blocks on standard error with exit status 0, so `l0 test` cannot show a
    leak

  *Combined ranking*, by how many of the three workers hit each limit and
  what it cost:

  | limit | workers | worst cost |
  |---|---|---|
  | no array or indexed table | 3 | wordfreq 9x Python, 61% of a Dijkstra query in counting trie nodes, Myers' worst case 70x a C array |
  | no type parameters | 3 | about 100 of 1,607 lines duplicated; no reusable map, set, or heap possible |
  | bytes are 24-byte cons cells | 2 | 24x memory; line-building half of minigrep's time |
  | no handle over bytes in memory | 2 | csvcol 4x slower to be testable; 68 lines of temporary-file setup |
  | files can only be emptied and rewritten | 1 | kv set linear in the store; crash safety impossible |
  | no way to learn a write to standard output failed | 1 | impossible: a filter that lost its output exits 0 |
  | arithmetic wraps silently, no bitwise operators | 1 | 75 lines of overflow checks and their test |
  | forwarding failures, no wildcard arm, whole-input main exits 0 | 1 each | minor |

  *Library and tool findings*, not language: `read_line`'s errors (all
  three); leaks invisible under `l0 test` (two); `tools/l0check` groups
  `lib/test.l0` with the program where `l0 test` does not (two); the shipped
  skill's `l0/L0.md` and `l0 check` paths don't exist in this repository
  (all three); `l0 run` cannot pass arguments; the skill doesn't say `main`
  belongs in its own file; the prelude's `length` and `append` are not tail
  recursive; the checker's "unknown type" doesn't name the type; spec 6.3
  doesn't say what `open_read` does on a directory, or whether a failed final
  flush changes the exit status.
- 2026-09-24: **the user agreed to the proposal.** First the library and tool
  fixes as one tooling item, [0017](0017-library-and-tool-fixes.md). Then
  close the I/O gaps as small language items:
  [0018](0018-write-failures-reported.md) write failures,
  [0019](0019-append-and-rename.md) append and rename, and
  [0020](0020-in-memory-handles.md) handles over memory. The next goal after
  them is arrays, with compact bytes and in-place update, starting from the
  research item [0021](0021-arrays-route.md). Type parameters are deferred:
  they would give up `list` being the only parametric type, for a cost the
  workers measured in duplicated lines rather than capability or speed.
  The three worktrees and their branches are removed, with the user's
  approval.
