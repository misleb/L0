# 0045: tooling: the tools stop running the compiler under stage 0

Kind: tooling
Status: done, changelog "The compiler's source is no longer run by stage 0,
and no language change for it"; Linux run with 0054, after a fix
Needs: 0044

## Why

[0044](0044-compiler-free-of-stage0.md)'s finding. `tools/l0check`,
`tools/l0c`, `tests/compiler`, and the bootstrap's seedless start run
`lib/prelude.l0` and `compiler/*.l0` under stage 0, which is all that keeps
the compiler from using type parameters and `eq` on lists. The seed already
builds a compiler that uses them (`roadmap/0044/proto.diff`, applied to the
concatenated compiler source: fixpoint, and the same IR for the real
compiler source), and stage 0 rejects that source at its first generic
header:

```
$ cp build/compiler-source.l0 tmp/0044/re.l0
$ patch -s tmp/0044/re.l0 roadmap/0044/proto.diff
$ build/l0i run tmp/0044/re.l0 < /dev/null
tmp/0044/re.l0:3566:6: error: expected a function name
```

A seed-built current compiler linked at `-O0` takes 0.4 s to build and
checks the compiler's own source in 0.25 s, where stage 0 takes 0.8 s.

## Done when

- one shared helper builds the current compiler from the seed when
  `lib/prelude.l0` and `compiler/*.l0` differ from the copy it was last built
  from (compared with `cmp`), or the seed or runtime is newer, writing to a
  temporary name and renaming it into place
- `tools/l0check` and `tools/l0c` use it, and `tools/l0c` no longer picks up
  a stale `build/l0c-native`; `tools/test.sh --compiled` still tests the
  bootstrapped compiler
- `tests/compiler` runs through it in `tools/test.sh`, against the same
  goldens, `--bless` blesses them there, and `--compiled` runs them as now
- `tools/bootstrap.sh` has no stage-0 start and no AGREEMENT check
- nothing outside `stage0/` and `tools/test.sh`'s `tests/lang` and
  `tests/check` loops runs `build/l0i`, checked with `git grep`
- AGENTS.md, the `l0-bootstrap` skill, README "How the compiler is
  tested", and the tools' headers say that stage 0 judges programs, not the
  compiler's source
- both suites green, the fixpoint holds, and `tools/l0check` accepts the
  compiler with `roadmap/0044/proto.diff`'s change made in a scratch copy
  of `compiler/lex.l0`

## Log

- 2026-10-05: proposed by 0044.
- 2026-10-05: started at the user's choice. Done (reasons in the changelog,
  "The compiler's source is no longer run by stage 0"):
  - `tools/compiler.sh`: `current_compiler` builds `build/l0c-current` from
    `lib/prelude.l0` and `compiler/*.l0` with the seed, linked at `-O0`,
    and keeps the input bundle beside it in `build/l0c-current.l0`; it
    rebuilds when the bundle differs (`cmp`) or the seed or runtime is
    newer, writing under temporary names and renaming. A source the seed
    rejects fails with the seed's diagnostics, naming file and line, and
    leaves nothing behind (checked with a deliberate type error in a
    scratch copy of `compiler/main.l0`)
  - `tools/l0check` and `tools/l0c` run it; `tools/l0c` runs `L0_COMPILER`
    instead when it is set, which `--compiled` does, and never a leftover
    `build/l0c-native`
  - `tools/test.sh`: the stage tests are built by it, linked at `-O0`, and
    built and run in parallel, then judged in order; `run_case` is split
    into `exec_case` and `judge_case` for that. The fast suite takes about
    9 to 10 s, where it took 6; one at a time it took 18. `--bless` over the
    whole fast suite left every expectation file unchanged
  - `tools/bootstrap.sh`: no stage-0 start and no AGREEMENT check; the seed
    binary is written under a temporary name and renamed
  - `git grep l0i` outside `stage0/`: only `tools/build.sh`, which builds
    it, and `tools/test.sh`'s `tests/lang` and `tests/check` loops
  - docs: AGENTS.md, the `l0-bootstrap` and `l0-code` skills (one file each:
    `.claude/skills` is a symlink to `.cursor/skills`, not a copy), README
    ("How L0 grows", "The standard library", "How the compiler is tested"),
    and the comments in `lib/prelude.l0`, `lib/io.l0`, `compiler/lex.l0`,
    and `compiler/parse.l0` that said stage 0 runs them. The bootstrap
    skill's fresh-clone recipe now includes `lib/prelude.l0` and drops the
    output tag, as README's does
  - a scratch copy of the tree with `roadmap/0044/proto.diff`'s change made
    in its `compiler/lex.l0`: its `tools/l0check` and fast suite (63) pass,
    its `--compiled` passes (110, fixpoint at 1,165,262 bytes), and stage 0
    rejects its compiler source at `compiler/lex.l0:21:6`
  - main tree: both suites green (63, 110), fixpoint unchanged at
    1,162,096 bytes, and the seed still up to date, since only comments in
    the compiler's source changed
  - Linux runs owed: Docker was not running. They matter here, since the
    tools are shell run by dash on Ubuntu, and `tools/test.sh` now starts
    background jobs
  - next: 0046
- 2026-10-06: the Linux runs, with 0054's tree, found a bug here: the
  compiler `tools/compiler.sh` builds would not link on either
  architecture, `build/l0rt.o: file not recognized`, so `tools/l0check` and
  the fast suite's stage tests failed, and with them `framework.sh`, which
  calls `l0check`. `build/l0rt.o` is bitcode, for `-flto` links, and
  `link_quick` linked it without `-flto`: macOS's linker takes a bitcode
  object regardless, GNU ld does not. Passing `-flto` fixed it, but made
  every rebuild of the checker's compiler about 3.8 s, since a bitcode
  object makes even an `-O0` link run LTO. Instead `tools/build.sh` also
  assembles the runtime as machine code, `build/l0rt-native.o`, which
  `link_quick` links without `-flto`. Then both suites passed on linux/arm64
  and linux/amd64 (63, 115), with the same results on macOS
