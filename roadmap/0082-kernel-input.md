# 0082: tooling: process images for a kernel's input

Kind: tooling
Status: done, changelog "A process's image is raw, as its kernel loads it,
and no language change for it"
Needs: 0083

## Why

The second of the two gaps [0074](0074-route-to-a-microkernel.md)'s Log
names before the kernel's own project. A kernel on the board reads its
processes from its standard input, which `l0 boot` loads, as
`tests/virt/user/kernel.l0` does. Its images are what
`l0 build --target proc` writes, as ELF, and what spec section 10.3 says a
kernel maps is the image's bytes from 0xC0000000, raw, which
`tests/virt/user/bundle.sh` and `tests/virt/proc/harness/boot.sh` make with
`llvm-objcopy`. A project using the installed toolchain has neither
script, and no `llvm-objcopy` named for it, so it cannot make a kernel's
input.

## The plan

`l0 build --target proc` and `l0 link --target proc` write the image as a
kernel loads it, raw, linked by `ld.lld --oformat binary` as the board's
image has been since 0083: what the toolchain writes for a target is what
that target's loader loads. A kernel that wants an ELF's segments, for
their permissions, is a reason to bring the ELF back beside it; nothing
here wants one yet. How a kernel's input lays the images out stays the
kernel's, as its calls are (spec section 6.15).

## Done when

- `l0 build --target proc` writes a raw image; the harness, `bundle.sh`,
  `tools/test.sh`, and `tools/bootstrap.sh` use it as it is, with no
  `llvm-objcopy`
- the driver's usage, `lib/AGENTS.md`, and spec section 10.3 say what it
  writes

## Log

- 2026-10-11: opened from 0074's Log beside 0081.
- 2026-10-13: narrowed, behind 0083. What to do with the images, which
  is the driver and its device, is to be the kernel's boot arguments
  (0083), not part of its input; this item is only the images, raw, as a
  kernel loads them, with standard input staying how they reach the
  board until a real board's initrd is needed.
- 2026-10-14: started. A raw image only, no ELF beside it: 0083 made the
  board's image what its loader loads, and a process's follows.
- 2026-10-14: done. `l0 build --target proc` links with `ld.lld --oformat
  binary`; the IR harness loads the images as they are, `fault.ll` linked
  raw too, and `bundle.sh` is now a plain concatenation, so nothing here
  runs `llvm-objcopy`. Spec 10.3 and `lib/AGENTS.md` say what the image is.
  Suites green: 65, 142, and `--virt` 127; no Linux run, since neither the
  runtime nor the emitter changed. With 0081, both of 0074's gaps are
  closed: what is left of it is item 7, the kernel in a project of its
  own, and item 8, the measure as a test.
