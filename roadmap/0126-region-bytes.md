# 0126: a region's bytes copied out as bytes, and bytes into a region

Kind: language
Status: done, changelog "A region's bytes are copied out as bytes, and
bytes into it"; aarch64 `--virt` green; not run on macOS, a Pi 5, or
riscv64's half of `--virt`
Needs: nothing

## Why

L0S's `probes/bytes/REQUEST-region-bytes.md`. A process reaches shared
and DMA pages only as a region, and the only way in or out is
`region_read8` to `region_write64`, one access at a time. Its file
server's windows (up to 64 KB a write or read), its disk buffer (32 KB),
and its network drivers' frames each become bytes a `region_read8` and a
cons cell per byte, then `bytes_from_list`, and go back a
`region_write8` a byte.

## The plan

- spec 6.12: `region_read_bytes r off n` and `region_write_bytes r off b
  i j`, the shapes of `space_read` and `space_write`; errors in the order
  region, count or range, offset; no alignment; widths the host's
- `runtime/l0rt.ll`: both, a volatile byte at a time
- `compiler/check.l0`, `compiler/emit.l0`: names, arity, types, result
  type, borrowing, declares
- tests: `check_errors`, `bundle_prelude` and `emit_tail` re-blessed;
  `tests/io` for `not a region` on a host with no regions; `tests/virt`
  reading fw_cfg's signature and writing to the serial port, and the
  three errors

## Done when

- the checklist in the `l0-bootstrap` skill

## Log

- 2026-10-27: opened from L0S's request; spec and changelog written.
- 2026-10-27: done. The first test read fw_cfg's 4 bytes at once and
  faulted: QEMU takes that register's reads only at offset 0, which is
  why the builtins are for memory. Multi-byte copies are tested on the
  aarch64 board's PCIe configuration space (`tests/virt/aarch64/
  region_copy`), which reads and writes as memory; `tests/virt/
  region_bytes` reads fw_cfg a byte at a time on both boards. `lib/io.l0`
  has `device_read_bytes` and `device_write_bytes`; seed refreshed.
