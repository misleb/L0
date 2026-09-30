# 0026: How L0 holds bytes one byte per byte

Kind: research
Status: done; a packed `bytes` type, 0032, after builtins stop taking over
programs' functions, 0031; then the library and programs, 0033
Needs: 0024

## Why

From [0014](0014-programs-round-two.md)'s limits
`0014/data-structures/limits/04-bytes-are-cons-cells.l0` and
`0014/bytes-encodings/limits/02-bytes-as-lists.l0`: holding bytes as a list
costs 24 bytes per byte, so json held an 11.5 MB document in 276 MB, and
building lines was half of minigrep's time. [0021](0021-arrays-route.md)
measured holding 10 MB: 242 MB as a list and 82 MB as an `(array int)`. A
packed type would hold it in about 11 MB.

Not ready: arrays, 0024, cut the worst case by three and may change what
those programs would be written as. This needs a program written with
arrays that still fails on memory or speed. Building an array from a list
peaks at both at once, since freed cells stay on the free lists, so reading
input straight into packed bytes or an array belongs here too.

**Earned by [0028](0028-programs-with-arrays.md).** Its json and sort hold
their input as an array and still peak at 25 bytes a byte, because a program
cannot learn its input's length before reading it, so the array doubles and
the last doubling holds both copies (`0028/text/limits/01-input-into-array.l0`,
re-checked: 10 MB of input peaks at 257 MB growing, 82 MB at exactly the
right size, 85 MB in 64 K chunks, 242 MB as a list; Python 18 MB). Words as
hash keys cost 24 bytes a byte too, 37 of wordfreq's 54 MB. The worker's
hypothetical is `(read_all 0)` returning packed bytes.

## Done when

A written finding, with measurements, that settles: whether a packed type is
needed or an input builtin reading into an array of the right size is enough
first (it alone would take 257 MB to 82); if a packed type, its builtins, how
string literals and the list-based library meet it, and its layout; what it
costs the properties the l0-bootstrap skill lists; and the language items it
breaks into, each one bootstrapped change.

## Log

- 2026-09-25: opened from 0021's finding.
- 2026-09-28: earned by 0028's text programs; made a research item, by the
  user's choice, since the question of what to build comes first.
- 2026-09-29: done. A prototype worker built both answers on branch
  `proto/packed-bytes`, each stage with both suites green, the fixpoint
  holding, and the seed refreshed. Re-checked in the main tree from an export
  under `tmp/`: both suites green (the compiled suite's `io/libdoc` fails
  only inside the sandbox, which refuses `l0 init`'s `.cursor/`; it passes
  outside), and the json and sort numbers below reproduced to the digit,
  output byte-identical to `json.tool` and `LC_ALL=C sort`, and clean under
  `L0_RC_CHECK`. The finding:

  **A packed type is needed; an input builtin alone is not enough.** Peak
  memory per input byte, and time, median of three on macOS arm64
  (`0026/bench/measurements.txt`, deleted by 0033; it is in git history):

  | program, input | today | `read_array` | `bytes` |
  |---|---|---|---|
  | json, 11.5 MB | 257 MB, 23.5, 0.28 s | 102 MB, 9.3, 0.21 s | 13.6 MB, 1.2, 0.20 s |
  | sort, 10 MB | 260 MB, 26.0, 0.25 s | 98 MB, 9.8, 0.19 s | 17.6 MB, 1.8, 0.08 s |
  | wordfreq wide, 10 MB | 54.2 MB, 0.42 s | | 25.0 MB, 0.25 s |
  | input alone, 10 MB | 257 MB growing | 93.6 MB | 12.5 MB |

  `(read_array h)`, every byte left on a handle in an `(array int)` of
  exactly that length, removes the doubling peak and nothing else: an int
  array still costs 8 bytes a byte. `bytes` holds input at about its size
  (Python's `read()` peaks at 18.3 MB), and sort is three times faster
  because it touches an eighth of the memory. `read_array` is dropped: with
  `bytes`, a program that wants an int array builds one from it in L0.

  **The type, as prototyped.** Six builtins: `read_bytes h` (every byte left
  on `h`; the next `read_from` says whether it stopped at the end, -1, or on
  a failure, -5, since handle states are sticky), `bytes_len`, `byte_at`
  (range error out of bounds), `bytes_from_list` (each element modulo 256),
  `bytes_to_list`, and `bytes_write h b i j` (bytes `i` up to `j`; 0, or -2
  if `h` is not writable). Layout: an array's header and length word, then
  the raw bytes, so freeing, `L0_RC_CHECK`, and live counts need nothing
  new; `read_bytes` reads straight into the block it returns. `bytes_len`,
  `byte_at`, and `bytes_write` borrow; the conversions consume. A loop over
  a read-only `bytes` parameter stays a `musttail` call with no reference
  traffic. Left out, since no program needed them: slices, comparison,
  hashing, update, literals. sort compares with `byte_at`, wordfreq hashes
  in L0, and string literals stay `(list int)`, converted where needed. The
  compiler's own IR grew 4%; the compiler does not use the type.

  **What it costs the properties.** One more type constructor, not
  parametric, so `list` and `array` stay the only parametric ones. No
  mutation: a `bytes` value never changes. Stage 0 cannot run any of it, as
  with arrays, so the builtins have no independent oracle and are tested by
  the compiled suite alone.

  **Three things the spec must settle, found by the prototype:**
  - A new builtin silently takes over any function of that name (spec 7:
    "in call position the builtin always wins"), and the program's own
    function then fails with a type error in its own code. The worker's
    first names broke three existing programs (`write_bytes` broke 0028's
    sort, `bytes_of` the kvlog test; `read_all` would have broken three
    files), so the prototype's names are ones nobody uses. Re-checked with
    a program that defines its own `flush`: `an argument of flush must be
    int, but this is (list int)`. This is 0031, and it comes first so that
    0032 can choose names for what they mean.
  - `bytes` is recognized only where a type is expected, not reserved,
    because the wordfreq test names a parameter `bytes`. Every other type
    name is reserved; the spec must say which rule `bytes` follows.
  - Spec 10.3 says a borrowing builtin's pointer result gains a reference.
    That holds for a result taken from the argument, the only kind today,
    and not for a new block, which is why the conversions consume.

  **Items.** 0031, builtins no longer take over a program's functions;
  0032, the `bytes` type and its builtins, one bootstrapped change since
  the compiler does not use them; 0033, a `lib/io.l0` function reading a
  handle into `bytes`, and the 0028 text programs moved onto it, which must
  follow 0032's seed refresh because `tools/l0` builds with the seed. The
  prototype's programs are kept in `0026/bench/stage2/` for 0033, with the
  measurement script; delete them when 0033 lands. (0033 did.)
