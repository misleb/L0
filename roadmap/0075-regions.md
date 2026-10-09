# 0075: regions: device and physical memory, read and written by width

Kind: language
Status: done, changelog "Regions: a program reads and writes a device's
memory"; passed on Linux arm64
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
- 2026-10-09: done. Section 6.12 has `region_open`, `region_read8` to
  `region_read64`, `region_write8` to `region_write64`, and `barrier`;
  section 8 their three errors (`not a region`, `region offset out of
  range`, `misaligned region access`, checked in that order) and the
  guarantee restated; 9.2 a host without devices; 10.3 the runtime calls,
  `l0_host_region` and `l0_host_barrier`, and the board's eight device
  ranges. Accesses are volatile and reach one device in order; only the
  barrier orders them against memory, and atomics wait for a kernel per
  core. `l0rt.ll` keeps a table of 64 regions and checks every access;
  `host-libc.ll` gives -3 and a fence; `host-virt.ll` checks a fixed table
  of the board's devices, where its boot map is Device-nGnRnE, and its
  barrier is `dsb sy`. The compiler knows them as int-only effects, no
  more. `lib/io.l0` wraps them as `IoDevice`, `open_device` giving a
  `DeviceOpened` whose `DeviceFailed` has `DeviceMissing` or
  `DeviceNoRoom`, and `device_read8` to `device_write64`, named for the
  noun so as not to shadow the builtins; an example drives the PL011.
  QEMU's devices answered every width, a 64-bit access split in two: the
  PL011's and a virtio-mmio transport's identification registers read as
  their devices fix them, and the GIC distributor's priorities read back
  what each width wrote. Tests: `tests/virt/device`, the driver this item's
  Why could not write, writing "hi" through the PL011's registers, and
  reads and writes of every width; `tests/virt/region_ranges`, what opens
  and what is -3 or -5; `region_range` and `region_align`, the errors;
  `tests/io/regions`, -3 for everything under an operating system, with a
  `.host` file since the board differs; `tests/io/region_not_open`;
  `tests/unit/device_test`; `check_errors`, `bundle_prelude`, and
  `emit_tail`; the library index. `roadmap/0074/proc.ll` gained the two
  host functions, so the prototype still builds. Fixpoint holds and the
  seed is refreshed. Both suites green (65, 135), `--virt` 71 passed and 52
  skipped, Linux arm64 green (65, 135).
