# 0146: the runtime's structure

Kind: tooling
Status: proposed
Needs: nothing

## Why

The runtime is 11,300 lines of hand-written LLVM IR, every constant in
decimal, with no generator, and it is the fastest-growing code in the
repository. The review found:

- every host defines every host function: 42 in `host-libc.ll`, 36 in
  `board.ll`, 34 in `proc.ll`, most of them stubs returning -3, 1, or 2,
  so each new builtin edits all three
- the device-tree walker is written three times in `board.ll`
  (`boot_args`, `boot_memory`, `boot_cpus`)
- `pi5-aarch64.ll` declares `@devices` as `[30 x i64]`, returns a count of
  15, and indexes it with `getelementptr [16 x i64]`; it works only
  because the GEP is not `inbounds`
- device addresses are duplicated in `runtime/board/*.ll` and
  `tests/virt/board/*.l0`; process layout numbers in `proc.ld`, `proc.ll`,
  `kernel.l0`, and the harness kernels
- three kernels track one ABI: the IR harness twice (about 1,300 lines
  each, 900 differing) and `kernel.l0`
- fixed limits as literals: 64 handles, 64 regions, 255 spaces, 8 CPUs by
  4 slots, 5 holes, 8 RAM ranges

## The change, in steps

1. `runtime/bare/absent.ll`: a default definition of every host function
   that reports the facility absent, linked by every target, with each
   host's file defining only what it has; needs each definition to be
   replaceable, by `linkonce` or by the manifest listing `absent.ll` last
2. one device-tree walker with a visitor, in `board.ll`
3. the Pi 5 table's type fixed, and a check in `tools/test.sh` that each
   board's device table and `tests/virt/board/*.l0` agree
4. the board files generated from a table by an L0 program, as the compiler
   emits IR from programs, the same table feeding the spec's board document
   (0141) and the tests' constants
5. the IR harness kernels retired if `kernel.l0` covers what they run, or
   the gap named

Each step keeps `--virt` green on both boards; the Pi 5 steps need a run on
the board, which only the user can do.

## Done when

- each step above is done or recorded as not worth it
- a new builtin touches `l0rt.ll` and the hosts that have it, not the ones
  that lack it
- `roadmap/l0s-adoption.md` says what L0S must rebuild or re-flash after
  each step that changes a board's image, and what it need not

## Log

- 2026-10-30: opened, from the review (its item 3.2); proposed.
