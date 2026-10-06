# 0045: tooling: the tools stop running the compiler under stage 0

Kind: tooling
Status: proposed
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
- AGENTS.md, both copies of the `l0-bootstrap` skill, README "How the
  compiler is tested", and the tools' headers say that stage 0 judges
  programs, not the compiler's source
- both suites green, the fixpoint holds, and `tools/l0check` accepts the
  compiler with `roadmap/0044/proto.diff`'s change made in a scratch copy
  of `compiler/lex.l0`

## Log

- 2026-10-05: proposed by 0044.
