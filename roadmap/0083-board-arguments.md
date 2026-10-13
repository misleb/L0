# 0083: the virt board gives arguments, by the arm64 boot protocol

Kind: language
Status: queued
Needs: 0081

## Why

A kernel must be told at boot what to do with the images it is given:
which process is the serial driver, and that driver's device and
interrupt, so that it can start the driver with them by spec section
10.3's arguments call rather than the driver naming the board (the reason
0077 made arguments a system call). Today `tests/virt/user/kernel.l0`
gets all of it from its standard input, in a format of its own, which
mixes the payload, the images, with what to do with it. Real boots keep
the two apart: the images as a loaded file, the configuration as boot
arguments. The board gives a program none (`roadmap/0083/why.l0`, which
prints its arguments):

```
$ tools/l0 run --target virt roadmap/0083/why.l0 -- driver=1 base=0x09000000 irq=33
l0: the virt board gives a program no arguments
```

and spec section 9.2 says it has none.

## What was found

With `roadmap/0083/probe.ll`, booted under QEMU 11.1.2:

- a bare-metal ELF, as `l0 build --target virt` writes today, gets no
  device tree: `x0` is 0 at entry, nothing is at the bottom of RAM, and
  `-append` goes nowhere. `runtime/host-virt.ll`'s memory map, which says
  QEMU puts the device tree at 0x40000000, is wrong for these images
- the same code given the arm64 boot protocol's 64-byte header, and
  booted as a raw image, gets the device tree's address in `x0`, with
  `-append`'s text in it, as `/chosen/bootargs`: the probe exits 3 with
  `-append` and 2 without

U-Boot and the Raspberry Pi's firmware boot an arm64 kernel the same way,
the Pi with `cmdline.txt` as its arguments; not tried here.

## The plan

- spec: section 9.2 gives the board arguments, and 10.3 says where they
  come from: the device tree the boot protocol passes, its
  `/chosen/bootargs`, split on spaces
- `runtime/host-virt.ll`: the boot protocol's header, `x0` kept, the
  device tree walked for `/chosen/bootargs`, `l0_host_arg_count` and
  `l0_host_arg` over them; its memory map corrected
- `tools/l0`: `--target virt` writes the raw image, `l0 boot` and
  `l0 run --target virt -- ARGS` pass the arguments by `-append`, and
  `l0 test --target virt` could name its test by argument, freeing
  standard input
- `tests/virt/user/kernel.l0` takes which process is the driver, and the
  driver's device and interrupt, from its arguments, and gives them to
  the driver by the arguments call

## Done when

- the checklist in the `l0-bootstrap` skill
- to be made precise when it starts

## Log

- 2026-10-13: opened at the user's request, after asking whether a kernel
  that launches processes from an image needs boot arguments. Queued, not
  started. 0082 narrows to raw process images, behind this.
