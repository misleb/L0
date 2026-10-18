# 0087: research: the route to riscv64, and what QEMU's board gives

Kind: research
Status: done
Needs: nothing

## Why

The user asked for the hosts without an operating system to run on
`qemu-system-riscv64` as well as `qemu-system-aarch64`, organized so that
later boards, the StarFive VisionFive 2 (JH7110: U74 cores, a PLIC, an 8250
UART, OpenSBI and U-Boot) and the Raspberry Pi 4 (BCM2711: Cortex-A72, a
GIC-400, a PL011, the arm64 boot protocol), are less work. Today the
aarch64 board is one file, `runtime/host-virt.ll`, and aarch64 is also in
spec 10.3 (the context, the system-call convention, the devices and
interrupts), in `lib/io.l0` (`trap_of` decodes the ESR and reads `x8`,
`user_context` puts sp at word 31), in `tests/virt/user/kernel.l0`, in
about 12 `tests/virt` programs, in the IR harness kernel, and in the tools.

## The route

Decided with the user: a builtin names the machine, so library and kernel
code can branch on it and the IR stays the same for every host (9.2); the
virt suite runs both architectures every time; the tools take `--arch`
beside `--target`, aarch64 by default, and `l0 boot` reads the arch from
the image's boot header.

1. 0088, tooling: split `host-virt.ll` and `host-proc.ll` into a part no
   machine decides, an architecture's part, a board's part, and drivers,
   and describe each target by a manifest the tools read. aarch64 only,
   behavior unchanged
2. language: `(machine)`, then the seed refresh
3. language: `lib/io.l0`'s `Trap` and `user_context`, and helpers for a
   system call's number, arguments, and result, over `(machine)`; the L0
   kernel onto them
4. tooling: per-architecture expectations and board constants for tests
5. language: the riscv64 virt board, without user mode or interrupts
6. language: its interrupts and timer
7. language: its user mode
8. language: the riscv64 process host, its system call for the clock, and
   the riscv64 IR harness kernel

## What was found

With `roadmap/0087/probe.ll` and `probe.ld`, booted under QEMU 11.1.2 with
`-M virt,aia=none -m 1G -semihosting` and its default firmware, OpenSBI
v1.8.1 fw_dynamic:

- OpenSBI enters a raw image at 0x80200000 in S-mode with a0 the hart, 0,
  and a1 the device tree, at 0xBFE00000 with `-m 1G`. It keeps
  0x80000000 to 0x8005FFFF from S-mode by PMP
- `-append` reaches `/chosen/bootargs`, and `-device loader` data at
  0x83FFFFF8 and file bytes at 0x84000000 are in RAM at entry
- semihosting works from S-mode: `:tt` opened in mode 8 writes to QEMU's
  standard error, and `SYS_EXIT`'s status is QEMU's (the probe exits 7)
- **OpenSBI prints its banner on every boot to QEMU's standard output**,
  through semihosting since `-semihosting` is on, whatever chardev
  `-semihosting-config` names, and on the 16550 without it. With the
  16550 on a chardev of its own, `-chardev file,path=/dev/fd/3` and
  `-serial chardev:...`, the program's standard output is the serial line
  alone, and QEMU's own standard output can be thrown away
- Sv39 with identity gigapages works, and `satp` keeps 16 ASID bits
- the device tree's `timebase-frequency` is 10,000,000; an SBI TIME
  `set_timer` of 100,000 counts raises STIP after about 104,000, and
  `set_timer(-1)` clears it
- the PLIC's S-mode context for hart 0 is 1 (the device tree's
  `interrupts-extended` lists 11 then 9); with source 10's priority 1 and
  the 16550's transmitter-empty interrupt on, a `wfi` with `SIE` clear
  wakes and the claim is 10
- the default CPU has Sstc, Svadu, and Sv57, which the U74 lacks; SBI
  `set_timer` and Sv39 need neither
- `-mcmodel=medany -mno-relax` puts nothing in small-data sections here,
  and the container's ld.lld 18 links the probe; the layouts collect
  `.sdata` and `.sbss` anyway
- the compiler's own IR, `bootstrap/stage2.ll`, compiles for riscv64 at
  `-O2`, so LLVM honors every `musttail`; running it is item 5's fixpoint

The devices, from QEMU's device tree: the 16550 at 0x10000000 (0x100,
interrupt 10), the goldfish RTC at 0x101000 (interrupt 11), 8 virtio-mmio
transports from 0x10001000 (0x1000 each, interrupts 1 to 8), fw_cfg at
0x10100000 (0x18), the test finisher at 0x100000, the CLINT at 0x2000000,
and the PLIC at 0xC000000 (95 sources).

## Log

- 2026-10-17: opened at the user's request, with the route above agreed.
  Probe written and booted; findings above. Next: 0088.
