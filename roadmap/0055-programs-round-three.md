# 0055: A third round of ordinary programs

Kind: program
Status: active
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
