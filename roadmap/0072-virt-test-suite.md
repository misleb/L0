# 0072: tooling: the compiled suite and the fixpoint run on the virt board

Kind: tooling
Status: queued
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
