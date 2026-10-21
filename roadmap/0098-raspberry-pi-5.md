# 0098: the Raspberry Pi 5

Kind: language
Status: done, changelog "The Raspberry Pi 5"; built and linked, and its
shared parts run on QEMU's aarch64 board entered at EL2, but not run on a
Pi 5
Needs: nothing

## Why

The user asked for an L0 target for the Raspberry Pi 5. A program cannot
be built for it:

```
$ tools/l0 build --target pi5 lib/examples/hello.l0 -o tmp/0098/hello.img
l0: unknown target pi5; the targets are host, virt, and proc
```

0087 and 0088 split the host so that a later board is a part, a layout,
and a manifest, and named the Pi 4 as the example: an arm64 board with a
GIC-400 and a PL011. The Pi 5 has both, and four things QEMU's board hid:
it enters the image at EL2 behind a resident BL31, its devices are above
4 GB, outside the 4 GB translation, it has no semihosting and no loader,
and its RAM starts at 0 and is 2 to 16 GB.

The user has no Pi 5 at hand and asked for parity with the aarch64 virt
board: console, arguments, standard input, the clock, regions, frames and
user mode, and interrupts.

## The plan

Spec 10.3 and the changelog first, then runtime and tools, then tests.

- spec and changelog: a third board (done)
- `runtime/arch/aarch64/boot.ll`: the EL2 drop, TCR T0SZ 25 with IPS 40
  bits, a 512-entry boot map, the header's board word
- `runtime/bare/board.ll`: standard input from the device tree's initrd,
  weak `__input_*`, `l0_board_map_ram` called for each `/memory` range
- `runtime/dev/pl011.ll`: `l0_pl011_drain`; `runtime/bare/psci.ll`
- `runtime/board/pi5-aarch64.ll` and `.ld`, `runtime/targets/pi5-aarch64.target`
- the virt boards: the 512-entry map, a no-op `l0_board_map_ram`, the tag,
  and QEMU's virtualization on for aarch64
- tools: `--target pi5`, `T_BOARD_TAG`, a board with no emulator refused by
  `l0 boot`, `run`, and `test`, `l0 card`, and the test lists that take
  boards from manifests with a `T_QEMU`
- tests: the whole virt suite, now entered at EL2; `-initrd` input; an image
  check of the Pi's build and of `l0 card`

## Done when

- `tools/test.sh`, `tools/test.sh --compiled`, and `tools/test.sh --virt`
  green, and `tools/build.sh` builds `pi5-aarch64`'s runtime
- `l0 build --target pi5` links a program, with the magic and the tag in
  its header, and `l0 card` writes its files
- the Log says what a first run on a board must check; **no run on a Pi 5
  is claimed**, since none was made

## Log

- 2026-10-20: opened at the user's request, planned from the Pi 5's device
  tree (raspberrypi/linux `bcm2712.dtsi`, rpi-6.12.y), its TF-A port, and
  Raspberry Pi's documentation. The spec and changelog are written. Next:
  the boot code.
- 2026-10-20: implemented as planned, with these differences: the UART
  interrupt is enabled as both GIC IDs 152 and 153 rather than by reading
  the stepping register; a layout with no loader gives `__input_len` as a
  word that is always 0 rather than weak symbols; the Pi's UART region is
  0x1000 so its PrimeCell ID registers are reachable; the watchdog is not a
  region (its address was not in the device tree); the initrd test is
  aarch64's, since QEMU puts riscv64's inside the heap. On QEMU's aarch64
  board, now entered at EL2, the whole suite runs through the new EL2 drop
  and 39-bit translation. `tools/test.sh` 65, `--compiled` 149. Left for a
  first run on a Pi 5, which has not been made: UART output at all; the EL2
  drop; `/memory` on 2, 4, 8, and 16 GB boards; BL31's pages inside the
  first gigabyte block; `kernel_address`, `device_tree_address`, and the
  initramfs address honoured; the arguments the firmware appends to
  `cmdline.txt`; PSCI `SYSTEM_OFF`; the 152 and 153 numbering; user mode and
  interrupts on a Cortex-A76; coherent DMA, which it is not. `tests/virt/pi5/
  uart.l0` is the first program to run there.
