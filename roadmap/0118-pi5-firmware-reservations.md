# 0118: does the Pi 5's frame pool include RAM the firmware keeps?

Kind: research
Status: done
Needs: nothing

## Why

L0S's `probes/memory/REQUEST-pi5-firmware-reservations.md` (2026-10-25)
reports memory corruption on a Pi 5 since its `hvs` driver started, and
asks the runtime to leave out what the firmware reserves: `/memreserve/`
entries, `/reserved-memory` children that are not `reusable`, and
`simple-framebuffer` nodes. Its reasoning: the firmware's log puts the
HDMI framebuffer at 0x3F800000, 1920x1080 at stride 3840, and the pool's
first piece was taken to end at 0x3FC00000, so page tables, which come
from the top, would land in the framebuffer. It had not read the tree as
the firmware patches it.

## Findings

A copy of the runtime under `tmp/0118/` printed the device tree, as the
firmware handed it over, in hex on the UART before anything else, on a
2 GB Pi 5 booted with a monitor on HDMI0 (log: `hotplug 1`, `FB0 ... base
0x3f800000`). Decompiled with `dtc`:

- `/memory@0` is `0` to `0x3F800000` and `0x40000000` to `0x80000000`.
  The firmware leaves its framebuffer out of `/memory` itself; booted with
  no monitor (0110), the first range ran to `0x3FC00000`.
- There are no `/memreserve/` entries in the header, and no
  `simple-framebuffer` node. The root has a property
  `memreserve = <0x3f800000 0x800000>`, 0x3F800000 to 0x40000000, which
  lies outside `/memory`.
- `/reserved-memory`: `atf@0`, 0 to 0x80000, below the image; `linux,cma`,
  `reusable`; `nvram@0`, filled in as `0x3FD23180` for 0x4A bytes, outside
  `/memory`; `nvram@1`, still `<0 0 0 0>` and disabled.
- `(frame_free_count)` at boot was 259,605, against 260,627 without a
  monitor (0110): 1,022 pages fewer, the 4 MB from 0x3F800000 to
  0x3FC00000 less a two-page difference in what the two programs' inputs
  and arguments took.

So on this board and firmware (EEPROM 2026/05/26) no frame or page table
lies in the framebuffer, nor in anything else the tree reserves: every
reservation is below the image or outside `/memory`. The request's
premise, that the first piece ends at 0x3FC00000 with a monitor, does not
hold; L0S's count of 320,879 came with its own heap and stack sizes and
was not compared with a boot without a monitor.

## Outcome

No language change: the runtime's comment ("the firmware a board's host
runs under keeps below the image") holds, with the addition that the Pi
5's firmware also shrinks `/memory`. Changelog "The Pi 5's firmware keeps
its framebuffer out of /memory". L0S's corruption has another cause; of the
request's own list, its `hvs` driver programming the IOMMU the firmware's
display path uses, and the mailbox changes of the same evening, remain.
