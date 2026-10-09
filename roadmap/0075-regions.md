# 0075: regions: device and physical memory, read and written by width

Kind: language
Status: queued
Needs: 0074

## Why

No L0 program can touch a device. This drives the PL011 serial port on
QEMU's virt board: wait while the transmit FIFO is full, flag register bit
5, then store the byte to the data register.

```
(def uart_base () int 150994944)      ; 0x09000000

(def put ((b int)) int
  (if (eq (bit_and (load32 (add (uart_base) 24)) 32) 32)
      (put b)
      (store32 (uart_base) b)))
```

```
$ tools/l0check roadmap/0074/progs/uart.l0
roadmap/0074/progs/uart.l0:8:20: error: unknown function load32
```

Every driver a microkernel runs starts here, and so does the kernel's own
interrupt controller: [0074](0074-route-to-a-microkernel.md)'s stub drives
the GICv2 with six 32-bit accesses. 0074 found that a raw load and store
at an address would give the checker nothing, and could reach the
runtime's own heap, so the facility is a handle over a range instead.

## Done when

- the checklist in the `l0-bootstrap` skill
- the spec has regions as 0074's finding sketches them: a handle over a
  range of device memory or of a frame the host gives out; reads and
  writes of 8, 16, 32, and 64 bits at an offset, each a volatile access, an
  offset out of range or misaligned for its width a runtime error, as
  `array_get`'s is; a barrier; and a host with no such range, an
  operating system's among them, giving -3 to open it (section 9.2). What a
  read returns is an integer, never a pointer, and no region covers the
  runtime's own memory, which is what section 8's guarantee then says.
  Whether accesses are ordered beyond volatility is decided, and the
  changelog says why, with a kernel per core in mind
- section 10.3 has the runtime functions and the host functions behind
  them; `host-virt.ll` opens a region only over a device range of the
  board, from the device tree or a table, and `host-libc.ll` gives -3
- the library wraps them in types, as `IoOpened` does an open
- `tests/virt` has the PL011 driver above, written with regions, writing
  through the serial port and reading its flag register; and tests of the
  bounds, widths, and the -3 on the host
- the compiler does not use regions, so this is one bootstrapped change

## Log

- 2026-10-09: opened by 0074's recommendation, item 1, and queued at the
  user's request.
