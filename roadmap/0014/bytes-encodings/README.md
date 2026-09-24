# Programs: bytes, encodings, and comparing sequences

Three ordinary programs written to find out what L0 should gain next, from
what they hit rather than from opinion. Each directory has the program, its
`main` in a separate file (since `l0 test` supplies its own), unit tests,
a script that measures it, and a README of what happened.

```sh
tools/build.sh && tools/bootstrap.sh && cp build/stage2 build/l0c-native
export L0_COMPILER=$PWD/build/l0c-native L0_RUNTIME=$PWD/build/l0rt.o
tools/l0 test programs/base64/base64.l0 programs/base64/base64_test.l0
tools/l0 test programs/linediff/linediff.l0 programs/linediff/linediff_test.l0
tools/l0 test programs/minigrep/minigrep.l0 programs/minigrep/minigrep_test.l0
```

Measurements are best of three on an Apple M4 Pro, with Homebrew clang 23.

## The programs

| program | status | tests | measurement |
| --- | --- | --- | --- |
| [base64](base64/README.md) | done | 18/18 | 10 MB: encode 0.06 s, decode 0.14 s, 1.6 MB peak; byte-exact round trip |
| [linediff](linediff/README.md) | done | 13/13 | 5,000 lines, 1% changed: 0.01 s, 9.6 MB, minimal (108 = diff's 108) |
| [minigrep](minigrep/README.md) | done | 20/20 | 20 MB: 0.5 to 2.3 s, grep 0.07 to 0.46 s; matches grep on 923 random patterns |

All tests also pass under `L0_RC_CHECK=1`. Real runs of all three binaries
under it report no leak and no use after free.

## The limits, ranked by what they cost

Each has a smallest program with the checker output or a measurement in
[`limits/`](limits), and the code that L0 would allow in
[`hypothetical/`](hypothetical).

1. **01 — a failed write to standard output cannot be detected.**
   *Impossible.* `write_to` succeeds because it buffers. Spec 6.3 says a
   write failure is reported by `close`, but `close` refuses handles 0 to
   2, and the flush at exit happens after `main` has returned its status.
   `base64 >&-` exits 0 having lost everything, where every Unix filter
   exits nonzero. There is no workaround. The fix is small: a `flush`, or
   letting `close 1` flush and report.
2. **02 — bytes are cons cells.** *Costliest workaround, in time.* A line
   must be built as one 24-byte cell per byte and then reversed. minigrep
   is 5 to 15 times slower than grep, and building lines alone accounts
   for 0.43 s of its roughly 1 s on 20 MB (0.06 s to read the same bytes
   without keeping them). Matching then walks lists, with a runtime call
   and reference counting per step. It hits every text program, and the
   compiler too.
3. **03 — no arrays.** *Costly in the worst case only.* linediff rebuilds
   Myers' diagonal vector as a new list at every step and carries edit
   lists in place of a trace. That is fine at 1% changed (0.01 s) but
   8.4 s and 596 MB when every line differs, against 0.02 s for Apple's
   diff. The bare vector loop is 1.40 s in L0 and 0.02 s in C. The
   workaround cost no extra code, because lists that share structure
   replace indexes neatly, so this ranks below 02.
4. **05 — no handle over bytes in memory.** *Workaround cost 68 lines.*
   Code written against handles, which is what the spec recommends for
   large input, can only be unit-tested through files in `/tmp`: 42 lines
   of plumbing in base64's tests and 26 in minigrep's. The tests also need
   a writable `/tmp`, and their fixed file names would collide if two runs
   overlapped.
5. **04 — no generic functions.** *Workaround cost 10 lines.* `rev` and
   `length` are copied for `(list Front)`, `(list Edit)`, `(list Tok)`, and
   `(list (list int))`, five times across the programs. Each copy is cheap,
   but the cost recurs in every program that has a data type.

Not limits: L0's lack of bitwise operators cost base64 nothing measurable,
since `div`, `mod`, and `mul` on non-negative bytes are exact, and decoding
is as fast as the system's.

## Mistakes made writing L0, and what caught them

Every file type checked on its first run through `tools/l0check`, and
`L0_RC_CHECK` never fired. The mistakes were in logic, and `l0 test` caught
all of them:

- **linediff's tie rule was backwards.** When a move down and a move right
  reach the same point, I chose right, so a changed line printed `+new`
  before `-old`. The script was still minimal, so only the golden
  output test caught it, not the property test.
- **A wrong expected value in a test.** I built an expected list of lines
  with `split_spaces`, which drops empty strings, so the test expected no
  blank line. `l0 test` showed both lists as L0 literals, which made the
  cause obvious.
- **A wrong line in a hypothetical file.** My first `rev` in
  `hypothetical/04` took `head` of a possibly empty list to avoid writing
  `(nil t)`. Nothing checks hypothetical code, and I only caught it on
  rereading. Hypothetical files deserve the same suspicion as real code.
- **Nearly a bad measurement.** The first base64 encode took 0.53 s,
  because macOS checks a new binary on its first launch, against 0.06 s
  afterward. Every script now takes the best of three.

Strict `and` and `or` never bit, because I kept to the skill's advice and
guarded every `head` with an `if`.

## Problems in the spec, the skill, the library, and the tools

- **Spec 6.3 is silent on write failures to handles 0 to 2.** It says
  `close` reports write failures, and that `close` refuses those handles,
  but never says what happens when the flush at exit fails. In practice
  the exit status stays whatever `main` returned (limit 01).
- **`lib/io.l0` contradicts the skill.** The skill says to test for -1 and
  for other negative results separately, or a failed read looks like a
  short file. But `read_line`, `file_read_line`, and `read_line_from` all
  stop at any negative byte, so a failed read does look like the end of
  input. linediff and minigrep each had to write their own line reader to
  report failures.
- **`tools/l0 run` cannot pass arguments to the program.** Every argument
  is taken as a source file, and the program runs with none. Programs with
  arguments have to use `l0 build` and then be run. The skill's loop
  shows `l0 run prog.l0 < input` and does not mention this.
- **The skill never says a tested program's `main` must be in a separate
  file.** It says test files do not define `main`, but the program under
  test cannot either, since `l0 test` adds one. So every program here is
  split into `NAME.l0` and `NAME_main.l0`. The convention should be
  written down.
- **The skill calls L0 "small, pure"**, while the spec says it is no longer
  pure. The skill's paths (`l0/L0.md`, `l0 check`) are the ones `l0 init`
  scaffolds, not this repository's (`spec/L0.md`, `tools/l0 check`).
  `tools/l0check` needs `lib/prelude.l0 lib/io.l0 lib/test.l0` passed
  explicitly, while `tools/l0 check` adds them itself.
- **The checker says `unknown type` without naming the type**
  (`hypothetical/02` shows it), while `unknown function` names the
  function.
- **`head` and `tail` are runtime calls** (spec 10.3), so every list step
  is a call into another object file that clang cannot inline. I did not
  profile how much of minigrep's matching time that is, but it is paid on
  every step of every list walk, and the rev in limit 02 (0.28 s of pure
  head, tail, and cons over 20 MB) suggests it is a large share. It is an
  implementation choice rather than language, so it is likely the
  cheapest improvement for list-heavy programs.
