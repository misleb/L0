# 0115: an L0 microkernel and its processes on the Raspberry Pi 5

Kind: program
Status: done
Needs: 0110

## Why

The goal is a microkernel that runs drivers and programs as processes on
bare metal. `tests/virt/user/kernel.l0` is that kernel on QEMU; 0110 showed
the Pi 5 runs spaces, threads, and interrupts, but no kernel with process
images had run there.

## Done when

- `kernel.l0` runs on a Pi 5 through `tools/pi5-run`, its processes built
  with `--target proc` and bundled into its standard input, for a test
  that touches no device, one that sleeps, and the serial driver
- what fails is fixed, or opened as an item

## Log

- 2026-10-25: done, on a 2 GB Pi 5. `release` printed `frames back`;
  `sleeper` printed its `.out` and `.err` and the status line for 70; the
  serial test, with the driver given `1:70816632832 1:153 1:pl011`, first
  stopped after `a `: the driver waited for a PL011 transmit interrupt
  after every byte, which QEMU raises, but a real PL011 with FIFOs on, as
  the firmware leaves it, raises only as the FIFO drains through its
  trigger level. The first byte passed on a stale interrupt status. The
  driver now waits for the UART to be idle and turns the FIFOs off before
  unmasking the interrupt; then the Pi printed `serial.out` exactly, and
  `--virt` stayed green. `lib/AGENTS.md` says both. Scratch in `tmp/0115/`.
  Next: PCIe interrupts (0116) and a first RP1 driver as a process (0117).
