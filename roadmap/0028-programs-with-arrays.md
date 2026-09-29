# 0028: Programs written with arrays

Kind: program
Status: done
Needs: 0024

## Why

Arrays (0024) and release at last use (0023) are in, measured only on three
benchmark loops. 0025 (updating an array held inside another) and 0026
(bytes one byte per byte) each wait for a program that needs them. The user
chose a round of programs written with arrays to find out what arrays make
possible, where they still fall short, and whether either item is earned.

## The task

Three workers, in parallel, three programs each, as 0014 did:

- **grids:** Conway's Life on a 1,000 by 1,000 torus for 100 generations; a
  shortest-path solver for a maze read from a file, up to 2,000 by 2,000; a
  Sudoku solver by backtracking
- **text at scale:** word frequencies with a hash table in arrays, against
  0014's wordfreq; a JSON pretty-printer that holds its input as an array,
  against 0014's json (11.5 MB, 873 MB peak); `sort` of the lines of a 10 MB
  file
- **algorithms:** Kruskal's minimum spanning tree with union-find over 100,000
  edges; edit distance of two 10,000-character strings by dynamic
  programming; Dijkstra with a binary heap in an array, against 0014's paths

They run as ordinary subagents in the main tree, not in worktrees, since
worktrees are placed outside `$HOME/projects` (`.cursor/rules/local-tmp.mdc`).
Each writes only under its own `tmp/0028/AREA/`, and the coordinator copies
what is worth keeping into `0028/`. Each writes unit tests with `l0 test`,
checks updates with `L0_ARRAY_STATS`, measures time and memory, and records
every limit with its smallest program and the code it would have written.

## Done when

- every limit reported has been re-checked in the main tree and logged here
- each of 0025 and 0026 is either earned by a program, with that program as
  its Why, or left waiting with the reason

## Log

- 2026-09-28: opened. `tools/l0` and `tools/l0check` now build and run in the
  checkout's `tmp/` rather than the system's temporary directory, which they
  used before; an installed `l0` still uses the system's. Three workers
  launched.
- 2026-09-28: **grids reported.** life, maze, and sudoku work, pass their
  tests under `L0_RC_CHECK`, match Python byte for byte, and run 4 to 14
  times faster than it (life 1000×1000×100 in 0.72 s against 9.82 s). The
  worker read the spec, the shipped skill, `lib/io.l0`, and two test files,
  and no compiler or runtime source. Re-checked in the main tree:
  - **nested update copies the row** (`limits/01`): 4,000,000 updates of a
    2000×2000 array of rows make 4,000,000 copies in 0.65 s, against 0
    copies in 0.10 s with the placeholder swap. The maze's array-of-rows
    version copies 2.1 million rows and is 7.7 times slower than flat. This
    is the program 0025 was waiting for.
  - **a read-only helper costs its reference counting** (`limits/02`): 50
    million lookups through a helper taking the arrays take 0.27 s, taking
    the ints 0.09 s, inline 0.07 s; inlining the candidate check took sudoku
    from 0.29 s to 0.16 s. Removing it would need the compiler to borrow a
    parameter the callee only reads, which section 10.3 would have to allow.
  - **section 6.5 is wrong about data values** (`probes/probe.l0`): an array
    in a data value matched at its last use updates in place (0 copies in
    1,000), whether the value came from a parameter or a function's result;
    it copies only when the value is still used after the match. Arrays in
    arrays copy. The shipped skill repeats the error. `(array_new h
    (array_new w x))` shares one row, so each copies on first update, which
    nothing documents.
  - also: no array helpers in the library, and no generic ones possible
    (grow and trim written twice, for `(array int)` only); 8 bytes per cell
    (a 2001×2001 maze is 32 MB of 127), not enough to earn 0026; no bitwise
    operations (masks by `div` and `mod` 17 times slower than flag arrays).
  - doc fixes: the repo's `l0-code` skill still says to run programs with
    `build/l0i run`, which rejects arrays; a missing period in section 10.3.
- 2026-09-28: **algorithms reported.** mst (100,000 nodes, 1,000,000 edges,
  0.26 s and 64 MB against Python's 0.82 s and 217 MB), editdist (two 10,000
  byte files, 0.48 s against 8.71 s; the alignment by Hirschberg's method in
  linear space), and dijkstra all work, pass their tests, and update every
  array in place at full size. The worker read the spec, the shipped skill,
  and the two comparison programs, and no compiler or runtime source.
  Re-checked in the main tree:
  - **dijkstra with a binary heap in an array: 1.45 ms a query**, all 100
    answers right, against 4.9 ms for `tests/io/array_paths` (0024 measured
    9.2 ms before link-time optimization) and Python's 11.3 ms.
  - **a read after an `array_set` of the same array, in one expression,
    copies it silently** (`limits/03`): `(array_set (array_set h 0 (array_get
    h k)) 1 (array_get h (add k 1)))` copies on each of 100,000 moves (0.20
    s); binding both reads with `let` first copies nothing. Operands that
    are variables are taken last, but a read nested inside a later operand
    is a later use, so the inner `array_set` never has the only reference,
    and the read cannot be moved earlier because `array_get` can fail and
    section 8 fixes which error comes first. It passed every test and made
    each query slower than 0014's tries; only `L0_ARRAY_STATS` showed it.
    The shipped skill's "reading the array in the same expression is fine"
    is wrong as written.
  - **nested update**, again (`limits/01`): a 5,000 by 5,000 table filled by
    nested update took 11.3 s and copied 125 billion words, against 0.06 s
    flat and 0.23 s with the swap. editdist did not need it, since a flat
    table was the better layout anyway.
  - **arrays in data values do not copy** when the value is taken apart at
    its last use: union-find's `UF` and dijkstra's `Graph` hold several
    arrays each and never copied, costing only a block per rebuild. Agrees
    with grids that section 6.5 and the skill are wrong.
  - also: no pair type (a heap as one interleaved int array, the named
    workaround, 0.27 s; two arrays in a data value 0.49 s; an array of
    boxed pairs 0.70 s and 45% more memory), and one-use data types for
    every function returning two things; no type parameters, cheap here
    since almost everything is `(array int)`.
  - doc fixes: nothing warns that nested `(push a (push b acc))` pushes `b`
    first; `rand_next` exists only under `l0 test`.
- 2026-09-28: **text reported.** wordfreq (a hash table in two arrays, 0.16
  s on 10 MB against 0014's 0.56 s rebuilt today and Python's 0.29 s), json
  (the input as an array read twice by index, no tree: 0.38 s and 257 MB on
  11.5 MB, against 0014's 0.68 s and 439 MB today and Python's 0.56 s and
  111 MB; identical to `json.tool --indent 2`), and sort (lines as indices
  into one byte array, a bottom-up merge sort: 0.26 s and 260 MB on 10 MB,
  against `sort`'s 0.04 s and 22 MB) all work, with no copies. The worker
  read the spec, the shipped skill, and 0014's wordfreq and json, and no
  compiler or runtime source. Re-checked in the main tree (`limits/01`, 10
  MB of input): an array that doubles as it is read peaks at 257.3 MB, one
  of exactly the right size at 81.5 MB, 64 K chunks in an array of arrays at
  84.9 MB, a list at 241.5 MB; Python holds it in 18 MB. A program cannot
  learn its input's length first, so holding input as an array costs what a
  list does, which **earns 0026**: its hypothetical is `(read_all 0)`
  returning packed bytes. Words as keys cost 24 bytes a byte (36.8 of
  wordfreq's 54 MB), which supports it. No program needed a nested update.
  No floating point, so json cannot print `1.50` as `1.5`.
- 2026-09-28: **all three in.** Every program works, and every one beats
  Python on time; memory is where L0 still loses, on text. Proposed:
  - **doc fixes now**: section 6.5 on data values (they update in place when
    taken apart at their last use), shared rows from nested `array_new`,
    `array_new`'s cost, the missing period in 10.3; in the shipped skill the
    same, plus the read-after-set trap, holding input as an array, and push
    order; in the repo skill, `build/l0i run`; the checker's unknown-type
    message not listing arrays; `L0_ARRAY_STATS`'s third line
  - **0026 is earned** by json and sort, and should start as research: a
    packed type, or first an input builtin that reads into an array of the
    right size, which alone takes 257 MB to 82
  - **0025 is split**: grids' maze pays 7.7 times for the natural
    array-of-rows code, but in every program a flat array was the better
    layout and the workers reached for it; leave it proposed, with the
    skill telling agents to use flat arrays
  - **new candidate**: borrowing a parameter the callee only reads (45% of
    sudoku)
  - pairs and type parameters recur in all three, still at the cost of a
    workaround rather than a capability
- 2026-09-28: **the user chose all four**: the doc fixes as 0029, now; then
  borrowed parameters as 0030 and nested update 0025, queued in that order;
  and 0026 as research. The workers' programs, limits, hypotheticals, and
  reports are copied into [0028/](0028/) (sources only; their generated
  inputs stay in `tmp/`). Done.
