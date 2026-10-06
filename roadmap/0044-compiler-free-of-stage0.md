# 0044: research: how the compiler and the prelude stop being run by stage 0

Kind: research
Status: done; the tools first (0045), then the prelude (0046), then the
compiler (0047)
Needs: nothing

## Why

The bootstrap starts from the seed, but stage 0 still runs the compiler's
own source in three places, so the compiler and `lib/prelude.l0` may use
only the L0 stage 0 knows (ints, bools, lists, data):

- `tools/l0check` runs `lib/prelude.l0` and `compiler/*.l0` under
  `build/l0i` (`tools/l0check:57`), so it always checks with the current
  source
- `tests/compiler`, 14 stage tests, runs the same sources under `build/l0i`
  (`tools/test.sh:436`), and their goldens are blessed that way
- `tools/bootstrap.sh:118` falls back to stage 0 when there is no seed

A function any program may now write cannot go in either file:

```
(def (count_of T) ((x T) (xs (list T)) (n int)) int
  (if (is_empty xs)
      n
      (count_of x (tail xs) (if (eq x (head xs)) (add n 1) n))))

(def main ((input (list int))) (list int)
  (if (eq (count_of "a" (cons "a" (cons "b" (nil (list int)))) 0) 1)
      "ok\n"
      "no\n"))
```

```
$ tools/l0check roadmap/0044/generic.l0
ok: roadmap/0044/generic.l0 type checks
$ tools/l0 run roadmap/0044/generic.l0 < /dev/null
ok
$ build/l0i run roadmap/0044/generic.l0 < /dev/null
roadmap/0044/generic.l0:1:6: error: expected a function name
roadmap/0044/generic.l0:7:12: error: unknown function 'count_of'
```

Every feature since arrays has paid for this:

- the compiler keeps 24 per-type `rev`, `length`, and `append` copies
  (`rev_tokens`, `rev_tys_onto`, `length_exprs`, `append_sigs`, ...), the
  `(list int)` `rev`, `length`, `append`, `any_eq`, and `index_of` at the
  top of `compiler/lex.l0` (0040, 0043), and `ty_eq`, `tys_eq`, `bools_eq`,
  and 75 calls to `list_eq` that `eq` would replace (0042)
- its nine parser and checker result types are one `Result` or `Option`
  shape (0035), and `PadMap` is one of the four copies of a string hash trie
  (0041)
- the library is split in two by what stage 0 can run: generic helpers,
  `Option`, and `Result` live in `lib/io.l0` though they are not I/O
  (changelog "The library declares Option and Result"), and the prelude's
  `rev` and `length` left it for the same reason (0040)
- the compiler cannot use arrays, bytes, or `eq` on lists, so it reads its
  input as a cons cell per byte

0035 named this a separate decision: the compiler adopting a new feature
ends the stage-0 run of its tests and needs a new rule for blessing them.

## The question

What runs `tools/l0check` and `tests/compiler` once stage 0 cannot run the
compiler's source, and what keeps those tests honest without an independent
oracle? Weigh at least:

- running both through a compiler bootstrapped from the current source,
  as `--compiled` already does: what `l0check` costs per call then (time a
  bootstrap against today's stage-0 run), and whether a cached build keyed
  on the sources keeps it from ever being stale
- how `tests/compiler` goldens are blessed when the compiler is the only
  thing that can run them, given that `--bless` with `--compiled` is
  refused, and what the stage tests check that `tests/lang`, `tests/check`,
  and the compiled suite do not
- what stage 0 still guards afterward: `tests/lang` and `tests/check` stay
  differential, and say so
- the bootstrap's stage-0 fallback, and whether a fresh clone needs it
- whether `lib/prelude.l0` and `lib/io.l0` should become one library once
  nothing forces the split, and what `tools/l0`, `tools/bundle.sh`, and
  install would change
- the order of the steps, given the two-step rule in `l0-bootstrap`: the
  tools stop depending on stage 0 first, then the compiler starts using
  new features, one bootstrapped change at a time

## Done when

- the Log has a finding: each place stage 0 runs compiler source, what
  replaces it and at what cost (measured), the blessing rule for the
  compiler's own goldens, and what stage 0 still guards
- the recommendation names the first item, tooling or language, with its
  Why, and the items after it in order (for example: the tools stop using
  stage 0; the prelude takes back the generic helpers; the compiler drops
  its copies)

## Log

- 2026-10-05: opened at the user's choice, over a `hash` and library map,
  function values, and a third program round. Evidence above gathered in
  the main tree; `roadmap/0044/generic.l0` is the program in the Why. Next:
  read the tools, measure `l0check` under stage 0 against a bootstrapped
  compiler, and write the finding.
- 2026-10-05: **finding**, from the tools as they are and measurements in
  `tmp/0044/` on macOS arm64, while a Linux amd64 run under emulation
  loaded the machine (so absolute times are high, and ratios are what
  count).
  - **Where stage 0 runs compiler source, and nowhere else.** `tools/l0check`
    (`:57`), `tools/l0c` when `build/l0c-native` is absent (`:59`),
    `tests/compiler` in the interpreted suite (`tools/test.sh:436`), and the
    bootstrap's start when there is no seed (`tools/bootstrap.sh:118`). No
    `tests/lang` or `tests/check` program includes `lib/`, so stage 0 runs
    `lib/prelude.l0` only as part of the compiler.
  - **What the stage-0 run of `tests/compiler` actually checks.** Not the
    compiler's logic: stage 0 runs the compiler's own checker and emitter,
    so goldens such as `check_fn_params` and `check_params`, about features
    stage 0 has never had, are already the compiler's own output. What it
    adds is one comparison, the compiler interpreted against the compiler
    compiled, on 14 inputs. `--compiled` already runs the same 14 against
    the same goldens through the bootstrapped compiler.
  - **What stage 0 still guards afterward.** `tests/lang` (23) and
    `tests/check` (21) stay differential, which is where stage 0's
    independent semantics matter: it judges the compiler's output on
    programs, not the compiler's source. The interpreted suite drops from 63
    tests to 49.
  - **A native checker is faster than stage 0, rebuild included.** The
    current compiler, compiled by the seed (one compile, no fixpoint) and
    linked at `-O0`, costs 0.14 s plus 0.27 s to build. It checks the
    compiler's own 198 KB of source in 0.25 s against stage 0's 0.8 s, and
    a small file in under 0.01 s either way, with byte-identical output
    (`-O2 -flto` as `tools/l0ll` links: 3.0 s to build, 0.15 s to check; a
    whole bootstrap is 11 s). So `l0check` loses nothing by leaving stage 0
    if its compiler is rebuilt only when the sources change. Exact
    staleness needs no hash: keep the concatenated source it was built
    from, and `cmp` it, plus the seed's and runtime's mtimes; build to a
    temporary name and rename, so concurrent checks cannot see half a
    binary.
  - **A stale-compiler hazard exists today.** `tools/l0c` uses
    `build/l0c-native` whenever it exists, and only `--compiled` refreshes
    it, so after a compiler edit `tools/l0c` silently runs the previous
    compiler. The same cache fixes it.
  - **The seed already compiles a compiler that uses type parameters.**
    Prototype `roadmap/0044/proto.diff`, applied with `patch` to the
    concatenated source `tools/bootstrap.sh` writes to
    `build/compiler-source.l0`: the compiler source with `lex.l0`'s
    `(list int)` helpers replaced by `lib/io.l0`'s generic ones and
    `rev_tokens` calling generic `rev` at `Token`. Seed, then itself twice:
    fixpoint at 1,165,262 bytes (today 1,162,096), and it compiles the real
    compiler source to byte-identical IR. Stage 0 rejects it at the first
    generic header. Since 0038 and 0042 refreshed the seed, the first half
    of the two-step rule is done for type parameters and `eq`; only the
    tools stand in the way.
  - **A two-step violation shows up sooner.** Once `l0check` builds its
    compiler with the seed, using a feature the seed lacks fails the next
    check, naming the line. Today it fails at the next bootstrap, or, per
    `tools/bootstrap.sh`'s header, only in a fresh clone.
  - **Blessing.** The compiler stage goldens have always been the
    compiler's output, so the rule need not change: plain `--bless` in the
    interpreted suite blesses them, now by running them through the cached
    compiler, and `--bless` stays refused with `--compiled`. What is lost
    is the interpreted-against-compiled comparison on those 14 inputs, and
    `--compiled` keeps a weaker one: the seed-built compiler against the
    self-built one, on the same goldens.
  - **The bootstrap's stage-0 start** is unreachable as long as the seed is
    checked in, and cannot work once the compiler uses a feature stage 0
    lacks; nor can its AGREEMENT check. Both go.
  - **The library stays two files, for a better reason.** The compiler
    links `lib/prelude.l0` and not `lib/io.l0`, and needs no I/O. So the
    pure, generic definitions (`rev_onto` to `index_of_from`,
    `array_resize`, `array_copy_onto`, `Option`, `Result`) move back to the
    prelude, and `lib/io.l0` becomes I/O only, as its name says. That
    supersedes changelog "Why lib/io.l0, though they are not I/O".
    `tools/l0`, `tools/bundle.sh`, and install need no change. The compiler
    declares no `Option`, `Result`, `Some`, `None`, `Ok`, or `Err`, so none
    collides with its names.
  - **Recommendation, in order:**
    1. 0045, tooling: the tools stop running the compiler under stage 0. A
       seed-built current compiler, cached as above, runs `tools/l0check`,
       `tools/l0c`, and `tests/compiler` in the interpreted suite;
       `--compiled` keeps using the bootstrapped one. The bootstrap loses
       its stage-0 start. AGENTS.md, both copies of the `l0-bootstrap`
       skill, README "How the compiler is tested", and the tools' headers
       say what stage 0 still guards. The Why is the measurements and
       prototype here.
    2. 0046, language: the prelude takes back the generic definitions and
       `Option` and `Result`, and `compiler/lex.l0` drops its copies. One
       bootstrapped change, since the seed knows both features.
    3. 0047, language: the compiler uses them, replacing its other 19
       per-type `rev`, `length`, and `append` copies, its remaining 73
       `list_eq` calls, `ty_eq`,
       `tys_eq`, and `bools_eq` with `eq`, and its nine result types with
       `Option` and `Result`. This can be split by file if it is too large
       for one review.
    - Later and separately: the compiler reading its input as `bytes`, and
      `PadMap` on a library map once a `hash` item exists.
- 2026-10-05: `tools/linux-test.sh arm64 amd64` on this tree, which changes
  only `roadmap/`: both suites green on both (63 and 110), which discharges
  the runs 0025 to 0037 owed. Next: 0045.
