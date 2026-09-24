# 0016: A local image for the Linux test runs

Kind: tooling
Status: done
Needs: nothing

## Why

Every runtime and emitter change is checked on Linux as well as macOS, by
running both suites in an `ubuntu:24.04` container. Each run installs clang
with `apt-get`, so it needs the network, can fail on a mirror, and takes
whatever clang Ubuntu ships that day. The command is also a long one-liner
retyped each time. For 0015 the x86-64 run under emulation took about 14
minutes.

## Done when

- a Dockerfile under `tools/linux/` builds an image with clang and a non-root
  user, and pins the clang version it installs
- one script builds the image when it is missing and runs both suites for
  `arm64` or `amd64`, copying the working tree into the container, since a
  bind mount ignores the permission bits `tests/io/filecopy.sh` checks
- the `l0-bootstrap` skill names it next to the other commands
- nothing is pushed to a registry

## Log

- 2026-09-24: opened at the user's request, as its own commit after 0015.
- 2026-09-24: done. `tools/linux/Dockerfile` installs `clang-18` on
  `ubuntu:24.04` with a `tester` user, and `tools/linux-test.sh` builds
  `l0-linux-test:ARCH` when it is missing, streams the working tree in with
  `tar` rather than mounting it, and runs both suites, printing each
  summary line or the whole log of a failing suite, and exiting 1 if either
  failed. On arm64 the first run took 1 min 52 s with the image build, and
  later runs 12 s; amd64 under emulation took 6 min 10 s with its image
  build. Both pass both suites. A throwaway failing test failed both suites and the
  script's exit status. Named in the l0-bootstrap skill and `AGENTS.md`.
