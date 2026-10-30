# 0146: the runtime's structure

Kind: tooling
Status: active
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
- 2026-10-30: active; step 3 done. The Pi 5's `@devices` is indexed as
  the `[30 x i64]` it is, where its GEPs said `[16 x i64]` and read past
  their type's end for every device from the ninth; `tools/test.sh
  --virt` first checks that `tests/virt/board/virt-ARCH.l0`'s devices lie
  within the runtime table's and its non-devices outside it
  (`board_table_check`), for both boards. `--virt` green; the Pi 5 image
  builds, not run on a board. Next, step 1: `runtime/bare/absent.ll` with
  every host function `weak` and reporting its facility absent, linked by
  every manifest, then each host's stubs deleted one file at a time,
  `--virt` after each; `host-libc.ll`'s stubs stay, since it must be the
  same text on macOS and Linux and is linked outside the manifests. Steps
  2 (one device-tree walker), 4 (board files generated from a table), and
  5 (the IR harness kernels retired) wait behind it; 5 needs a list of
  what the harness runs that `kernel.l0` does not.
- 2026-10-30: step 1 done. `runtime/bare/absent.ll` defines, `weak`, the
  27 host functions as a host lacking each facility gives them (spec 9.2),
  and every manifest links it last; `board.ll` lost its 6 such stubs and
  `proc.ll` its 21, keeping 17 definitions, all real. A strong definition
  in a part replaces the weak one when the parts are linked into the
  program's module, before optimization; each part is compiled alone at
  -O2, where a weak body is not inlined. `host-libc.ll` keeps its own,
  being linked outside the manifests and the same text on both operating
  systems. `--virt` green on both boards, user mode among it, which shows
  the boards' own definitions win and a process gets the absent ones; the
  Pi 5 image builds, not run on a board. Next: step 2, one device-tree
  walker in `board.ll` for `boot_args`, `boot_memory`, and `boot_cpus`.
