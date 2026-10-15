# 0084: a frame's address, so a kernel can give a device memory

Kind: language
Status: done, changelog "A frame's address, so a kernel can give a device
memory"; passed on Linux arm64
Needs: 0078

## Why

L0S, the kernel's own project (0074's item 7), asked for it in
`probes/virtio-gpu/REQUEST-frame-address.md` there. Every virtio device on
the virt board works in memory it reaches by DMA, and its driver writes
that memory's address into the device's registers. Nothing gives the
address of anything (`roadmap/0084/why.l0`):

```
(def queue_address ((d IoDevice) (t int)) int
  (let q (frame_new)
    (device_write32 d (add (mul t 512) 128) (frame_address q))))
```

```
$ tools/l0check lib/io.l0 roadmap/0084/why.l0
roadmap/0084/why.l0:7:45: error: unknown function frame_address
```

The probe guessed the address from `host-virt.ll`'s allocator,
`0x98000000 + f*4096`, and with it got a correct display-info reply from
QEMU's virtio-gpu, so the address is all that is missing.

## The plan

- spec: `frame_address` in 6.13, its error in 8, 9.2's absence, 10.3's
  call, host function, and the board's answer; 6.12's `barrier` orders
  loads too, which a driver polling a device's reply relies on
- compiler: the name, its arity, its call and `declare`
- runtime: `l0_frame_address` over `l0_host_frame_address`; the board's
  is `frame_pa`, the others 2, `not a frame`
- `tools/l0`: modern virtio-mmio transports always, and `L0_QEMU_ARGS`
  for devices beyond the board's own
- `tools/install.sh`: remove the request templates retired in c5575cb,
  which an installed toolchain kept, pointing at the `l0-limits` skill
- tests: `check_errors`; `tests/io/frame_unknown`; `tests/virt/frame_dma`,
  a DMA round trip through the firmware configuration interface

## Done when

- the checklist in the `l0-bootstrap` skill, with the seed refreshed
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green
- L0S's probe, with `frame_address` for its guess, gets its reply booted
  with `L0_QEMU_ARGS` and no wrapper

## Log

- 2026-10-15: opened from L0S's request, and started.
- 2026-10-15: implemented as planned. `tests/virt/frame_dma` is a real
  DMA round trip with no extra device: the firmware configuration
  interface, given a request in a frame by its address, copies `QEMU`
  into it. Modern transports changed `tests/virt/device`'s version read
  from 1 to 2. Suites green: 65, 143 from 142, `--virt` 129 from 127;
  Linux arm64 65 and 143; seed refreshed, fixpoint holds. L0S's probe,
  copied to `tmp/`, with `frame_address` for its guess and booted by
  `tools/l0 run --target virt` with `L0_QEMU_ARGS="-device
  virtio-gpu-device"`, got `response type 0x1101, scanout 0 1280x800,
  enabled 1`. Done.
