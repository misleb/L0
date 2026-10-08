# 0071: a runtime for QEMU's virt board, and l0 build for it

Kind: language
Status: queued
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
  from `roadmap/0068/metal.ll`, as 0069's spec says a host without an
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
