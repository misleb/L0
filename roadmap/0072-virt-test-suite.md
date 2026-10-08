# 0072: tooling: the compiled suite and the fixpoint run on the virt board

Kind: tooling
Status: done, changelog "The fixpoint and the compiled suite run on the
virt board, and no language change for it"
Needs: 0071

## Why

The goal's measure, the compiler compiling itself on a machine with no
operating system to the same bytes, was met once, by hand, in
[0068](0068-route-to-bare-metal.md). Until a test checks it, any change can
lose it unseen.

## Done when

- `tools/test.sh --virt` runs the compiled suite's programs as images under
  QEMU, against the same expectations as `--compiled`, linking every image
  in one container rather than one container per image (0068 measured
  0.19 s of each `docker run` as start-up)
- a program needing what the board lacks, such as files, skips, by a rule
  stated in the script, rather than failing
- `tools/bootstrap.sh` can check the fixpoint on the board: the compiler,
  built as an image, compiles its own source to `bootstrap/stage2.ll`
- the time the suite takes under emulation is recorded here, which decides
  whether 0073 is needed

## Log

- 2026-10-08: opened by 0068's recommendation, item 4.
- 2026-10-08: 0071 added `tools/test.sh --virt`, which runs only
  `tests/virt`, each image linked by its own `docker run`. This item extends
  it to the compiled suite's programs and the fixpoint, and links them in
  one container.
- 2026-10-08: done. `tools/bootstrap.sh --virt` builds stage2 as a board
  image, boots it on the compiler's source, and requires stage3.ll's
  bytes: 5 s on the board. `tools/test.sh --virt` runs that, then
  `tests/lang`, `tests/compiler`, and `tests/io` on the board against
  `--compiled`'s expectations, then `tests/virt`: 66 passed, 0 failed, 50
  skipped, in 97 s. The skips are stated in the script: 34 for a `.sh`
  script, 16 for `tests/unit`, and any program with a `<stem>.host` file,
  of which there are none. A grep for file and argument builtins was tried
  first and dropped, since it skipped twelve stage tests for a parameter
  named `args`. One container, started once with the repository at its own
  path, links every image through `L0_VIRT_LD` and `docker exec`. The
  driver gained `l0 link`, and `tools/build.sh` builds `build/virt`.
  Recorded time: 97 s, of which linking one compiler stage test is 2.6 s,
  nearly all clang on the host, and booting it 0.14 s, so 0073 is
  dropped.
