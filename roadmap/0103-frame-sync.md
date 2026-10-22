# 0103: `frame_sync`, a frame's bytes made to agree between caches and memory

Kind: language
Status: queued
Needs: 0102

## Why

L0S's `probes/usb/REQUEST-pcie-rp1-cache.md`, its third ask. The Pi 5's DMA
is not coherent with the CPU's caches, and spec 10.3 says the host does no
cache maintenance "until a builtin that cleans and invalidates is added for
a driver that needs it". L0S's xHCI driver is that driver: it writes TRBs
into a ring's frame before ringing a doorbell, and reads events the
controller wrote into another. Its `probes/usb/want.l0`:

```
(def offered ((ring int)) int
  (frame_sync ring (to_device)))

(def polled ((events int)) int
  (frame_sync events (from_device)))
```

```
want.l0:14:3: error: unknown function frame_sync
want.l0:17:3: error: unknown function frame_sync
```

No L0 code can clean a cache line, and a process cannot name a frame.

## The plan

- decide first, in the changelog, between the request's `(frame_sync f
  dir)`, by line to the point of coherency over the host's map of the
  frame, and frames mapped non-cacheable, which the request weighs and
  turns down for the attributes mismatched against the host's cacheable
  1 GB blocks
- spec 6.13 beside `frame_address`: dir 1 cleans, 2 invalidates, 3 both;
  `not a frame`, and a new runtime error for a dir out of range; on a host
  whose devices are coherent, a `barrier`
- a host function for it in every host; on aarch64 `dc cvac`/`ivac`/
  `civac` by `CTR_EL0`'s line, then `dsb sy`; on riscv64 a fence
- compiler: the builtin; tests on both virt boards, where only its errors
  and its being a barrier can be seen
- the seed refreshed if the library wraps it

## Done when

- the checklist in the `l0-bootstrap` skill
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green
- L0S's `want.l0` checks

## Log

- 2026-10-21: opened from L0S's request; queued after 0102. Interrupts
  (virt's INTx and MSIs, RP1's through the MIP) the request leaves to one
  of their own, once its driver runs.
