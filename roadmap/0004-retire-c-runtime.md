# 0004: Retire the C runtime files

Kind: tooling
Status: done
Needs: 0003

## Why

After 0003, `runtime/l0rt.c` is linked by nothing and `runtime/l0core.c` only
by stage 0. Leaving them in `runtime/` misstates what compiled programs use.

## The change

- delete `runtime/l0rt.c`
- move `runtime/l0core.c` and `runtime/l0core.h` under `stage0/`, and change
  the include path in `tools/build.sh`; `stage0/l0i.c` is not edited
- update README.md ("Installing", layout), `AGENTS.md` layout, and the
  `l0-bootstrap` skill's list of pieces
- delete `roadmap/0001/`, since `runtime/l0rt.ll` supersedes the prototype

## Done when

- both test suites and the bootstrap pass
- no file outside `stage0/` is C

## Log

- 2026-09-23: opened from 0001's answers.
- 2026-09-23: done. `runtime/` holds only `l0rt.ll`; the only C files are
  `stage0/l0i.c`, `stage0/l0core.c`, and `stage0/l0core.h`. `l0i.c` was not
  edited: it finds `l0core.h` beside itself. `l0core.h`'s header comment no
  longer claims to be shared with compiled programs. Both suites pass, the
  fixpoint holds, and the seed is current, since nothing it is built from
  changed.
