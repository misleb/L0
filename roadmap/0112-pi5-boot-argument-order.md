# 0112: the Pi's firmware puts its arguments before the program's

Kind: language
Status: done, changelog "The Raspberry Pi 5's firmware puts its arguments
first"; run on a Pi 5; riscv64's half of `--virt` not run here
Needs: nothing

## Why

Spec 10.3 says of the Raspberry Pi's boot arguments that the firmware's
`cmdline.txt` is `bootargs`, "which that firmware may follow with arguments
of its own". 0110's `tmp/0110/basics.l0` printed `(arg_count)` and each
argument on a Pi 5, with `cmdline.txt` holding `first base=0x09000000
a:b`:

```
20
reboot=w
coherent_pool=1M
8250.nr_uart=1
...
vc_mem.mem_size=0x40000000
first
base=0x09000000
a:b
```

The firmware's 17 arguments come first and the program's last, the
reverse of the spec. A program that reads `(arg 0)` as its own first
argument, as `tests/virt/boot_args.l0` does, gets `reboot=w`; its count is
the program's plus 17, which depends on the firmware, the EEPROM, and the
board's model.

## What is not known

Whether any way of telling them apart exists: the arguments' order is the
only one, and a program cannot tell where its own begin. Candidates, to be
settled by the spec: the host gives only the arguments after a marker the
card writes; the host drops those it knows the firmware adds; or the spec
says the arguments are the firmware's and the program's together and
`boot_args` is a QEMU test.

## Done when

- spec 10.3 says what the board gives, by what the board did, and the
  changelog says why that choice
- `tests/virt/boot_args` is judged on the Pi 5 by what the spec then says,
  and the line in `l0 card`'s output, if any, follows
- `tools/test.sh`, `--compiled`, and `--virt` green, and a run on the board
  through `tools/pi5-run`

## Log

- 2026-10-24: opened from 0110's run of `basics.l0`. Next: choose between
  the three candidates; the first needs a marker in `l0 card`'s
  `cmdline.txt`, which the firmware keeps in order.
- 2026-10-25: the marker, `--l0-args`. Spec 10.3 and the changelog first;
  then `runtime/bare/board.ll`, which finds the last marker after splitting
  and offsets `l0_host_arg_count` and `l0_host_arg` by it (a change to the
  runtime and the tools only, so no compiler change and no seed refresh);
  `l0 card` writes it first in `cmdline.txt`, counted in the 65,535-byte
  limit; `tools/test.sh`'s Pi check expects `--l0-args one two:2`, and
  `--l0-args` alone with no arguments; the new `tests/virt/boot_args_marker`
  (board only, with a `.board` file) has two firmware arguments, the marker,
  a third, the marker again, and two of the program's. `lib/AGENTS.md`, which
  `l0 init` ships, no longer says nothing of the Pi has run on a board.
  `tools/test.sh` 65, `--compiled` 155, `--virt` on aarch64 175, all passed.
  riscv64's half of `--virt` could not run (no `qemu-system-riscv64`), but
  `board.ll`, which it shares, compiles for it. On the Pi 5, `basics.l0`
  with `first base=0x09000000 a:b` gave `3`, then those three, where it had
  given 20. Done.
