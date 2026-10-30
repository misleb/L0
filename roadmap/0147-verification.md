# 0147: the checks run on every change, by a machine

Kind: tooling
Status: proposed
Needs: nothing

## Why

"Not run" appears 59 times in the roadmap: on riscv64's half of `--virt`,
on Linux, on macOS, on a Pi 5. There is no CI. Since 2026-10-30
`qemu-system-riscv64` and `ld.lld` are on this host, so both boards run
here without a container, and the review ran them. What a machine can run
should not depend on a note saying it was not.

Also found: the compiler stage tests are launched with an unbounded
`stage_case "$name" &` (test.sh), about 50 parallel builds the script
itself estimates at over 1 GB each, outside the job pool every other suite
uses; `tools/l0` in a checkout compiles with the seed while `tools/l0check`
compiles with the current source, so they can disagree while the seed is
stale; `test.sh` has a skip branch matching a message the compiler no
longer emits; and the suite's parallel jobs raced to rebuild `lib/` after a
seed refresh, which 0133 fixed with a lock.

## The change

- a GitHub Actions workflow, on Linux amd64 and arm64 runners with LLVM,
  QEMU for both CPUs, and lld: `tools/test.sh`, `tools/test.sh --compiled`,
  `tools/test.sh --virt`, and `tools/bootstrap.sh`, on every push; the
  seed's staleness reported as a failure, so a refresh is never left
  uncommitted
- the stage tests under the job pool
- `tools/l0` saying which compiler it used when the seed is stale, or
  using the current one in a checkout
- the dead skip branch removed
- `tools/linux-test.sh` kept for macOS hosts, its skill text saying so

The Pi 5 stays outside CI; its items keep saying "not run on a Pi 5", and
nothing else needs to.

## Done when

- the workflow is green on `main` and fails on a deliberately broken
  branch
- the roadmap skill says CI runs the suites and what it cannot

## Log

- 2026-10-30: opened, from the review (its item 3.3); proposed.
