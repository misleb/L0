# Text tools: roadmap 0014, round two of ordinary programs

Three programs, each in its own directory with tests and a README:

| program | status | tests | checked against | time and memory |
|---|---|---|---|---|
| [wordfreq](wordfreq/) | done | 11/11 | Python, byte-identical at 10 MB | 2.13 s, 9.6 MB at 10 MB (Python 0.24 s) |
| [csvcol](csvcol/) | done | 18/18 | Python `csv`, byte-identical at 14.5 MB | 1.07 s, 1.6 MB at 14.5 MB (Python 0.19 s) |
| [calc](calc/) | done | 18/18 | Python evaluator, 200,000 lines | 0.99 s, 1.6 MB for 200,000 lines |

All three ran under `L0_RC_CHECK=1` with nothing left live. Each checks with
`tools/l0check` (given `lib/prelude.l0 lib/io.l0`, plus `lib/test.l0` for
tests) and with `tools/l0 check`. `measure.sh` is the timing script: it
reports the second of two runs, because a newly linked binary's first run on
macOS spends about a second being verified.

No generated input is kept. Each program's `gen.py` recreates it.

## Limits, ranked by what they cost

Nothing was impossible. Every limit had a workaround, and they are ranked by
what the workaround cost. Each has its smallest program under `limits/` and
the code I would have written under `hypothetical/`.

1. **[01] No array: nothing can update the i-th of many values in O(1).**
   It is the largest measured cost. wordfreq keeps its counts in a 62-line
   AVL tree and is 9 times slower than Python, and 1.0 s of its 2.13 s is
   rebuilding tree paths only to add 1 to a count. The minimal program, a
   byte histogram, takes 1.77 s with the best workaround (a depth-8 tree) and
   13.1 s with a list, where reading the input takes 0.04 s. An array whose
   `set` works in place when the count is 1 would also be the first thing to
   earn roadmap 0013's release at last use, which was dropped because it
   made nothing possible.
2. **[02] A byte source cannot be an argument.** It costs a 4x slowdown in
   csvcol (1.07 s against 0.27 s), paid only so the parser can be tested on
   strings, plus a tokenizer written twice in wordfreq. The smallest fix is
   not function values but a handle over an in-memory string, together with
   one that captures output (option A of the hypothetical).
3. **[03] Functions are monomorphic.** It costs about 37 duplicated lines
   (`rev` twice more, and a merge sort bound to one type and one ordering).
   The duplication is easy to write and cost no speed; it drifts. A generic
   sort needs [02]'s function values too.
4. **[04] Arithmetic wraps silently, and there are no bitwise operators.**
   It costs 38 lines of sign analysis in calc, and 37 more of property test
   to trust them. It matters only to programs that must report overflow, but
   those cannot avoid it.
5. **[05] (minor) Forwarding a failure is a match arm at every call.** It
   costs 8 arms in calc's parser. The cost is nesting more than length.

## Mistakes I made or nearly made

None were L0 type errors. Every file type checked on its first run, so the
checker never fired on my code. The mistakes were ones no tool catches:

- **A property test that could not fail.** `rand_below` draws from the top
  32 bits of its state, so it only reaches about 2^31. My first
  `checked_mul` property drew factors meant to reach 2^40 but never reached
  overflow, so it would have passed with overflow detection deleted. I
  caught it by reading `lib/test.l0`, and the test now also asserts that
  some products overflowed.
- **A dead, wrong helper.** `add_byte` in wordfreq was never called, and was
  wrong. The checker does not report unused functions. I found it by
  rereading.
- **Numbers written before they were measured.** I put estimated timings, a
  line count, and a guessed checker message into the limit files, then
  measured and replaced every one. The guessed message was wrong in wording
  and position.
- **A timing artifact.** The first run of each new binary took about a second
  longer, which made reading 10 MB look like 1.19 s rather than 0.04 s.
  `measure.sh` exists because of it.
- **`L0_RC_CHECK` under `l0 test`** would not have caught a leak in a test,
  and I nearly relied on it. The runtime reports live blocks on stderr and
  leaves the exit status 0, and `l0 test` shows stderr only for a failing
  test. I checked leaks by running the built programs directly.

## Spec and skill findings

1. **`tools/l0check` and `l0 test` disagree about `lib/test.l0`.**
   `tools/l0check` makes `lib/prelude.l0` and `lib/io.l0` the prelude group
   when they are passed, but puts `lib/test.l0` in the program group. So a
   test file that defines `pass`, `fail`, `read_all`, `hex_digit`, or any
   other function `lib/test.l0` defines passes `l0 test` but fails
   `tools/l0check` with `function pass is already defined`. I reproduced
   this.
2. **Leak reports are invisible under `l0 test`**, as above. Either `l0 test`
   should fail a test that leaves blocks live when `L0_RC_CHECK` is set, or
   the skill should say to check leaks outside it.
3. **The shipped skill's paths do not match this repository.** It says
   `l0/L0.md`, `l0/examples.l0`, and `l0 check`, which is the layout
   `l0 init` scaffolds. Here they are `spec/L0.md`, `lib/examples.l0`, and
   `tools/l0 check` or `tools/l0check`. It is easy to work out, but it is the
   first thing a reader hits.
4. **`read_line` cannot report a read error.** `lib/io.l0`'s `read_line` and
   `file_read_line` treat every negative result as end of input, although
   spec 6.3 and the skill both insist that -1 and the other negatives be told
   apart. A program built on lines cannot follow that advice without
   rewriting `read_line`.
5. **Spec 6.3 does not say what `open_read` does on a directory.** On macOS
   it succeeds, and the first read returns -5, so csvcol can only say "input
   or output failed" for `csvcol /tmp 1`.
6. **The prelude's `is_lower` is true for `_`.** That is right for the
   compiler's names and a trap for text tools. The skill lists `is_lower`
   among the helpers to reach for without saying so. I noticed it by reading
   the prelude and wrote my own range check.
7. **A program's `main` must live in its own file to be tested,** since
   `l0 test` supplies a `main`. The skill implies this ("put its logic in
   functions") but does not say it. Every program here is split into
   `NAME.l0` and `main.l0`.
