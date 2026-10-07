# 0055: A third round of ordinary programs

Kind: program
Status: done
Needs: nothing

## Why

The queue is empty. Since 0028, L0 has gained bytes (0032), a clock (0034),
type parameters (0036, 0038), `eq` on any type (0042), typed open failures
(0050), `hash` (0052), and `(Map K V)` (0053), and no program round has used
any of them. Every candidate left open waits for code that needs it:

- from 0051: a persistent map, for code that keeps old versions; an ordered
  map, with `compare`
- from 0041: `compare`, and function values
- from 0049: typed failures for reads, closes, flushes, and renames
- from 0014 and 0028, named but never earned: floating point (0028's json
  could not print `1.50` as `1.5`), bitwise operations (masks by `div` and
  `mod` 17 times slower than flag arrays), arithmetic that wraps silently (75
  lines of overflow checks in 0014), and a pair type (an interleaved heap the
  named workaround, boxed pairs 2.6 times slower)

[0014](0014-programs-round-two.md) and [0028](0028-programs-with-arrays.md)
are the model: write real programs, record where L0 stops with the smallest
failing program, and let that choose.

## The task

Three workers, in parallel, three programs each, chosen to push on the
candidates above:

- **numbers and bits:** CRC-32 and SHA-256 of a file, checked against
  `cksum`/`crc32` and `shasum -a 256`; an exact rational calculator reading
  expressions with `+ - * /` and parentheses, printing results in lowest
  terms and to a fixed number of decimal places; a sieve of Eratosthenes to
  100,000,000 held as a bitset
- **generic structures:** a binary-heap priority queue and an ordered set,
  each written once for every element type and used at two of them; an LRU
  cache over the library's `Map`, driven by a trace of 1,000,000 requests;
  a text editor's buffer with undo and redo, reading a script of edits,
  that keeps old versions
- **tools that handle failure:** an archiver that packs files named on the
  command line into one file and unpacks them again, with a checksum per
  file; a log rotator that renames `log`, `log.1`, ... `log.N` and starts a
  new one, safe if interrupted; a `tee` that writes standard input to
  several files and reports, per file, which failed and how

They run as ordinary subagents in the main tree, not in worktrees, since
worktrees are placed outside `$HOME/projects` (`.claude/rules/local-tmp.md`).
Each writes only under its own `tmp/0055/AREA/`, and the coordinator copies
what is worth keeping into `0055/`. Each writes unit tests with `l0 test`,
measures time and memory at the stated sizes against a reference (Python or
a system tool), and records every limit with its smallest program and the
code it would have written. A workaround is written only when named as one,
with its cost.

## Done when

- every limit reported has been re-checked in the main tree and logged here
- each candidate in the Why is either earned by a program, with that program
  as the Why of a new item, or left waiting with the reason
- the limits are ranked into a proposal for what comes next, which the user
  agrees to

## Log

- 2026-10-06: opened at the user's choice, over starting any one candidate
  directly. Three workers launched: numbers, structures, failure.
- 2026-10-06: **structures reported.** kmerge (a generic heap and ordered
  set, used at ints and strings), lru (capacity 10,000 over `Map`, 1,000,000
  requests), and editor (100,000 edits with undo on 100,000 lines) all work,
  pass 47 tests under the reference-count check, and match Python byte for
  byte. The worker read the shipped guide, skill, spec, `l0 doc`, and the
  examples, and the prelude's `Map` only to find limit 03's cause. Heap 1.25
  s against Python's heapq 2.46 s; LRU 1.16 s against `OrderedDict`'s 0.18
  s, 0.23 s with limit 03 fixed; editor 0.19 s against 0.71 s. Re-checked in
  the main tree (programs in `tmp/0055/structures/`):
  - **`map_remove` copies the marks array** (`limits/03`): a 10,000-key
    window slid 200,000 steps makes 84,043 copies and copies 2.75e9 words;
    with the worker's `hypothetical/map_remove_fixed.l0`, 0. The prelude's
    `map_shift` (`lib/prelude.l0:238`) reads `ms` in `(map_next j ms)`
    after `(array_set ms i mj)` in the same call: the read-after-set trap of
    0028's `limits/03`, now in the library, whose author knew the rule. Its
    doc's "amortized constant time" is false until fixed. This is a bug,
    queued as 0056; that the trap caught the library's own author is
    evidence the trap itself wants a language answer
  - **no ordering on a type parameter** (`limits/01`): `error: an argument
    of lt must be int, but this is T`. **No function values** (`limits/02`):
    `error: int_less is a function, and L0 has no function values`. The
    named workaround orders a closed sum `Key = KInt int | KStr bytes`, 5.2
    times on the heap, 1.2 on the set, and no record can be an element. A
    structural `compare` would have served all three programs; a function
    type, orders that are not structural. **Earns `compare`**, or function
    values; which first is for research once all three report
  - **keeping old versions copies whole** (`limits/04`): 198 µs and one
    whole array per edit of a 100,000-entry `Map` whose old version is
    kept, as spec 6.5 says. The editor wrote a 185-line persistent AVL tree
    instead. Supports a persistent map or sequence in the library, which an
    ordered one needs `compare` for
  - **no empty `(array T)` without a `T`** (`limits/05`): checks, then
    `head of empty list` at run time. The workaround, an extra empty case
    as `MapEmpty`, costs an arm per function; minor
  - pairs were not a limit: two-field data types served everywhere
  - doc findings: the prelude's "sort the keys if the order matters" cannot
    be followed for a generic key; `l0 check` accepts a file with no `main`,
    which nothing says. `lib/L0.md` lacking 6.9's last sentence is a stale
    build copy, refreshed by `tools/build.sh`, not a finding
- 2026-10-06: **numbers reported.** sums (CRC-32 and SHA-256), calc (exact
  rationals), and sieve (a bitset to 10^8) all work, pass 66 tests, match
  `cksum`, `shasum`, and Python exactly, and copy no arrays. The worker read
  the shipped guide, skill, spec, `l0 doc`, and the examples, and no
  compiler, runtime, or suite source. Re-checked in the main tree (programs
  in `tmp/0055/numbers/`):
  - **no bitwise operations** (`limits/01`): `error: unknown function
    bit_xor`. sums takes 9.3 s on 100 MB, the right SHA-256, against 0.43 s
    for `cksum` and `shasum` together; reading is 0.29 s of it. One xor
    through `hash/bits.l0`'s 137 lines of tables, `div`, and `mod` costs
    13.1 ns a step against 1.6 ns for the loop alone (`limits/02`). The
    bitset holds 63 bits a word. Spec 6.9 defines `hash` with xor and a
    logical shift, which no L0 program can write. Hit two programs of
    three, and 0028's grids before them: **earned**
  - **no big integers** (`limits/06`): `error: integer literal does not fit
    in 64 bits`. 47,596 of 100,000 expressions overflow 64-bit rationals;
    the named workaround, 336 lines of digit arithmetic, is exact but 26
    times slower than `--int64` and 5.5 times slower than Python's
    `Fraction`, partly its naive division
  - **arithmetic wraps silently** (`limits/05`): `(mul 4294967296
    4294967296)` prints 0, and the least integer negated stays itself.
    Checks by hand are about 45 of `rat.l0`'s 174 lines and still give 97
    false overflows without a widening multiply. 0014 met this too
  - **no bytes that can be updated** (`limits/04`): `unknown function
    bytes_set`, `bytes_new`. A flag per number costs a word: 802 MB to 10^8,
    against Python's bytearray at 115 MB
  - **no hexadecimal literals** (`limits/03`): `invalid character in
    integer literal`; constants parsed from strings at startup. Legibility
    only
  - **no top-level values** (`limits/07`): `each parameter is (name type)`;
    lookup tables threaded through nine functions. Signatures only
  - no function values: operations passed as int codes
  - findings: after a declaration fails to parse, the checker reports
    every later use of it as unknown (seen in `limits/03` and `07`), which
    misleads; the library parses hex (`hex_val`) and cannot print it; `l0
    check` accepting a file with no `main` is undocumented, which
    structures also found; the shipped docs do not say where `l0 run`
    builds
- 2026-10-06: **failure reported.** archive (pack and unpack with a
  checksum per entry; every one-byte change and every truncation of a sample
  refused), rotate (a journal per step; 536 interrupted runs and 200 random
  kills left nothing lost or duplicated), and tee all work and pass 38
  tests. Failures were provoked for real: a full disk image, an immutable
  file mid-rotation, read-only and missing directories, a closed and a
  broken pipe. The worker read the shipped guide, skill, spec, `l0 doc io`,
  and the examples, and no compiler, runtime, or suite source. pack 0.55 s
  against `tar`'s 1.52 s; unpack 0.43 s but 104 MB against 3.7 MB; tee 1.12
  s against the system's 0.19 s. Re-checked in the main tree (programs in
  `tmp/0055/failure/`, probes in `tmp/0055/recheck/`):
  - **the implementation breaks spec 6.3 three ways**, so these are bugs:
    - a broken pipe kills the program (`limits/06`): piped into `head -c
      10`, the flush returns -5 and the program prints its message and
      returns 3, and exits 141, by SIGPIPE. 6.3 says a program told of
      every failure keeps its status; section 8 says nothing of signals.
      One that carries on writing, as tee does, dies silently mid-copy
    - `open_read` of a self-referencing link, and of a name over 255
      bytes, returns -3, "no such file"; 6.3 gives -3 only for a file that
      does not exist, so both should be -5
    - started with standard output closed (`limits/07`), the first file
      opened takes handle 1 and gets both outputs, and the program exits
      0. 6.3 says the three are open from the start and is silent on a
      host that started the program otherwise: a spec gap
  - **no bounded read** (`hypothetical/01`): `unknown function
    file_read_some`. Reading is a byte at a time or everything; tee is 5.9
    times the system's, and unpack holds the whole archive, 28 times
    `tar`'s memory, since streaming would write before the checksum is
    known and a bad file cannot then be removed
  - **rename, flush, and close give codes, and six causes are one**
    (`limits/02`, `02b`): a read-only or missing directory, a directory as
    target, a full disk, and two renames all say "input or output failed";
    ignoring a failed rename checks and exits 0. 0049's remainder, earned
  - **no delete** (`limits/03`: `unknown function remove_file`): a failed
    pack leaves `OUT.partial`, the journal stays, old logs are renamed, not
    removed. **No directories** (`limits/04`: `unknown function
    make_dir`), and **no metadata** (`limits/05`): no listing, no mode or
    times, a size only by reading it all
  - the library's `IoFile` wrappers cost 2.7 times raw handles in a
    per-byte loop (`exp/`, not re-measured); tee's hot loop uses raw
    handles as a named workaround
  - hashing part of a bytes value was not a limit; neither were binary
    integers by `div` and `mod`, nor the exit status apart from SIGPIPE
  - doc findings: `CreateDenied` reads as if it covered a read-only
    directory, which comes out as "input or output failed"; the skill's
    "use the wrappers" should say what a list of `IoFile` costs; a failure
    "on write" can only mean a flush during the copy found lost bytes; a
    parameter named `data` gives a confusing second error
- 2026-10-06: **all three in**, and every program works: 151 tests, every
  output matching its reference. **Combined ranking**:

  | limit | workers | worst cost |
  | --- | --- | --- |
  | 6.3 broken: SIGPIPE, open codes, closed std handles | 1 | wrong exit status; output into the wrong file |
  | `map_remove` copies (0056) | 1 | LRU 5 times slower |
  | no bitwise operations | 1, and 0028 | hashes 22 times `cksum` + `shasum` |
  | no ordering on `T`, no function values | 2 | heap 5.2 times; no record as an element |
  | no bounded read; no bytes to update | 2 | tee 5.9 times; unpack 28 times memory; sieve 7 times |
  | rename, flush, close untyped and unforced | 1 | six causes one message; ignored failure exits 0 |
  | no delete, directories, metadata | 1 | partial files left; archive cannot keep modes |
  | overflow wraps; no big integers | 1, and 0014 | calc 5.5 times `Fraction` |
  | keeping old versions copies | 1 | 185-line persistent tree written by hand |
  | read-after-set copies silently | 1, and 0028 | caught the library's author (0056) |
  | hex literals, top-level values, empty `(array T)` | 1 each | legibility, signatures |

  Pairs were not a limit, nor were function values on their own except
  as the way to order. Proposed, for the user to agree: 0056 first, then
  the three 6.3 bugs as one runtime item, then bitwise operations; research
  on `compare` against function values, and on bounded reads with
  updatable bytes; then delete and typed rename, flush, and close as I/O
  items; and one doc and tooling item for the findings above. Waiting,
  with their programs recorded here: big integers and overflow,
  directories and metadata, a persistent map, hex literals, top-level
  values, and the read-after-set trap
- 2026-10-06: **the user agreed to the proposal.** Queued: 0056
  (`map_remove`), [0057](0057-io-keeps-section-6-3.md) (the three 6.3
  bugs), [0058](0058-bitwise-operations.md) (bitwise operations),
  [0061](0061-delete-a-file.md) (delete), and
  [0062](0062-typed-rename-flush-close.md) (typed rename, flush, and
  close). Opened: research [0059](0059-compare-or-function-values.md)
  (`compare` or function values) and
  [0060](0060-bounded-reads-and-updatable-bytes.md) (bounded reads and
  updatable bytes), and tooling [0063](0063-docs-and-tools-from-0055.md).
  The workers' sources, limits, hypotheticals, references, and reports are
  copied into [0055/](0055/), `tmp/0055/AREA/` becoming `0055/AREA/`; their
  generated inputs stay in `tmp/`, and each area's reference scripts
  regenerate them. Done.
