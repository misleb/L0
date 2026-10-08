# 0071: a runtime for QEMU's virt board, and l0 build for it

Kind: language
Status: done, changelog "A host without an operating system: QEMU's virt
board"
Needs: 0070

## Why

A program runs on bare metal today only through
[0068](0068-route-to-bare-metal.md)'s prototype scripts. The driver has no
way to ask for it:

```
$ tools/l0 build --target virt tmp/0068/hello.l0 -o tmp/0068/hello-virt.elf
l0: unknown option --target
```

## Done when

- the checklist in the `l0-bootstrap` skill
- `runtime/host-virt.ll` implements 0070's host interface for the board,
  from `roadmap/0068/metal.ll` (which supplied libc to `l0rt.ll` as of
  commit 146d854, and does not link with the `l0rt.ll` 0070 left), as 0069's spec says a host without an
  operating system behaves, with an allocator that splits and merges
  blocks rather than 0068's power-of-two classes
- `tools/l0 build --target virt` produces an image, linking it in a
  container from a Dockerfile under `tools/` while the host's `ld.lld` is
  blocked, and `tools/l0 run --target virt` boots it under QEMU with
  standard input and the exit status as `roadmap/0068/run.sh` passes them
- every case of section 9.2 holds on the board and has a test: opening
  for reading, renaming, and removing give -3, opening for writing and
  appending -9, `arg_count` 0, and the environment's settings unset
- 0068's programs in `roadmap/0068/progs/` give the same results through
  the driver; the board's peak memory for the compiler compiling itself is
  measured and recorded
- `roadmap/0068/` is deleted, since the real thing then exists

## Log

- 2026-10-08: opened by 0068's recommendation, item 3.
- 2026-10-08: done. `runtime/host-virt.ll` is the board's host file:
  0068's boot code, serial output, loaded input, and semihosting, behind
  0070's interface, with section 9.2's answers for files, arguments, and
  the environment, and an allocator with boundary tags and 64 bins that
  splits on allocation, merges on free, and grows in place. `runtime/virt.ld`
  lays out the image. `tools/l0` gained `--target virt` for `build` and
  `run`, and `boot`: clang merges the program, `l0rt.ll`, and the host file
  as bitcode with `-mlink-bitcode-file`, so `llvm-link` is not needed, and
  ld.lld links, from `L0_VIRT_LD` or a container from
  `tools/virt/Dockerfile`. `tools/install.sh` installs the board's runtime
  in `lib/l0/virt/` when clang can target aarch64. `tests/virt`, six
  programs, runs with `tools/test.sh --virt`. 0068's five programs give
  their results through the driver. The compiler, built from source with
  `--target virt`, compiles itself on the board to the seed's bytes in
  4.96 s; its heap peaks at 0x4040060 bytes, 64.3 MB, the runtime's first
  64 MB arena chunk and 256 KB of buffers, measured with a copy of the host
  file that records the highest block end. `roadmap/0068/` is deleted. No
  compiler change. Both suites green (65, 132), `--virt` 6 of 6, fixpoint
  holds, Linux arm64 green (65, 132), and an install into a fresh prefix
  boots `tests/virt/hosts.l0`.
