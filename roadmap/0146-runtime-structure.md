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
- 2026-10-30: step 2 done. `dt_walk(dtb, visit, cx)` walks the tree's
  tokens once and calls a visitor for each node's beginning and end and
  each property, which may stop it; `boot_args`, `boot_memory`, and
  `boot_cpus` are each a visitor, `args_visit`, `memory_visit`, and
  `cpus_visit`, with their state in a few words of `cx`, where each had a
  walk of its own. `board.ll` is 35 lines shorter. `--virt` green on both
  boards, its `-smp 4` CPU tests, boot arguments, RAM, and initrd among
  it; the Pi 5 image builds, not run on a board, whose firmware's tree is
  the one these read differently (arguments first, an initrd). Next:
  step 4, the board files and `tests/virt/board/*.l0` from one table, or
  step 5, which first needs a list of what the IR harness kernels run
  that `kernel.l0` does not.
- 2026-10-30: step 5's gap, compared. What each runs under `--virt`:
  both run every `tests/virt` program as a process, with its arguments,
  and both run `tests/virt/proc`'s with what their `.with` files name;
  `tools/bootstrap.sh --virt` runs the compiler's fixpoint as a process
  under each. `kernel.l0` also runs `tests/virt/user`'s eight `.procs`
  tests, the harness IR processes (`fault`, `selfwrite`, `bigbss`, a
  foreign CPU's) among them. It answers more: calls 1 to 13 and its own
  from 256 (6.15), where the harness answers 1 to 11 and so tests neither
  `release` (12) nor `unregion` (13); and it takes images of any size
  from its standard input, where the harness's slots are 4 MB. What the
  harness has that `kernel.l0` lacks:
  - *Arguments with a space.* `kernel.l0` takes its processes' arguments
    from its own boot arguments, which hold no spaces (9.2), so
    `tests/virt/proc/args`, whose second argument is `second arg`, runs
    under the harness only. `tools/test.sh` skipped every `.args` test of
    `tests/virt/proc` under `kernel.l0`; it now skips only one with a
    space, and runs the rest with their arguments as `0:VALUE`. Closing
    it means a way to give `kernel.l0` arguments with spaces, such as
    reading them from its standard input beside the images.
  - *Independence.* The harness is IR, compiled by nothing under test,
    running at EL1 or S-mode with its own page tables, ASIDs, and GIC or
    PLIC driver; `kernel.l0` is compiled by the compiler under test and
    runs processes through the board host's user-mode builtins
    (`board.ll`'s spaces, frames, and `user_run`). So a fault in the
    process host (`proc.ll`) shows under the harness alone, where under
    `kernel.l0` a fault in the board's user mode or the compiler could
    mask it or be blamed on it. This is the property stage 0 and
    `tests/backend` keep for the compiler.
  Recommendation: keep both harness kernels, as an oracle that is not
  the code under test, frozen as stage 0 is: no new system call is added
  to them, and a new one is tested under `kernel.l0`, as 12, 13, and the
  kernel's own already are. Retiring them would cost the only check of
  `proc.ll` that does not run through `board.ll` and the compiler. Step 5
  is therefore recorded as not worth it, for that reason; the space gap
  stays named above. `--virt` green on both boards after the test.sh
  change.
