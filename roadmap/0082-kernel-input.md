# 0082: tooling: process images for a kernel's input

Kind: tooling
Status: proposed
Needs: 0081

## Why

The second of the two gaps [0074](0074-route-to-a-microkernel.md)'s Log
names before the kernel's own project. A kernel on the board reads its
processes from its standard input, which `l0 boot` loads, as
`tests/virt/user/kernel.l0` does. Its images are what
`l0 build --target proc` writes as ELF, laid out raw from 0xC0000000,
which `tests/virt/user/bundle.sh` makes with `llvm-objcopy`. A project
using the installed toolchain has no such script and no `llvm-objcopy`
named for it, so it cannot make that input.

## The question

How the input is laid out is the kernel's, as its calls are (spec section
6.15), so the toolchain should write an image a kernel can load, not a
bundle in one kernel's format: most likely `l0 build --target proc
--raw`, or a raw image beside the ELF, leaving the bundle to the
project. Settle it when 0081 is done.

## Log

- 2026-10-11: opened from 0074's Log beside 0081.
