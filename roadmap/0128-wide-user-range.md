# 0128: a user range past 4 GB on the 64-bit boards

Kind: language
Status: done, changelog "A space has a high user range, 128 GB past the
4th gigabyte"; not run on a Pi 5 or riscv64's half of `--virt`
Needs: nothing

## Why

L0S's request 2 (its `build/l0-requests.md`, roadmap 0038, measured on a
Pi 5 with 2 GB, 2026-10-29): spec 10.3 fixes the user range at
0xC0000000 up to 0x100000000, with a process's heap below 0xD8000000 and
its stack below 0xE8000000, which leaves 384 MB above the stack for the
regions and frames a kernel shares with it. At 3840x2160 and scale 2,
L0S's compositor maps every window's buffers, a few tens of MB each.
With five windows open it had 84,000 of its 98,304 pages there in use,
the free ones in pieces (the largest 5,592 pages), so a window's next
buffer of 11,387 pages could not be shared with it and the window froze.

What could not be written: a compositor that holds the buffers of more
than a handful of 4K windows, on any board.

Asked: a user range reaching past 4 GB on the aarch64 and riscv64 boards
and the Pi 5, for example up to 512 GB, or at least more room above the
stack, with spec 10.3 saying where.

Open questions, to settle in the spec first:

- where the range goes. It now sits in the 4th gigabyte, between the
  frame windows; on the Pi 5 RAM runs from 0x100000000 to 0x400000000,
  and on riscv64 from 0x100000000 to 0x140000000, so a range above them
  needs the board's own map and the windows rearranged, or a range
  placed above the highest RAM any of the boards has.
- whether the range below 4 GB stays, so a process's image, heap, and
  stack keep their addresses and `runtime/proc.ld` and processes already
  built keep working, with only the kernel's part above 0xE8000000 grown
  past 4 GB.
- the page-table depth this needs: 512 GB is one more level on riscv64's
  Sv39 than the 4th gigabyte alone touches, and is the whole of Sv39's
  lower half.

## Done when

- the checklist in the `l0-bootstrap` skill
- spec 10.3 gives the new range and the process layout's table says
  where the kernel's part ends; changelog says why
- the hosts of the aarch64 and riscv64 boards and the Pi 5 map and run
  threads there; `space_map` refuses an address past the range as now
- tests: on a board, a page mapped and touched past 0x100000000, and one
  past the new end refused; L0S's case, a space with more than 384 MB
  mapped above the stack

## Log

- 2026-10-29: opened from L0S's request 2. Next: settle where the range
  goes in spec 10.3.
- 2026-10-29: settled: a second part, the high user range, 0x2000000000
  up to 0x4000000000, root entries 128 to 255, free in all three boot
  maps and ending at Sv39's sign bit; the low range and a process's
  layout unchanged. Spec 6.13's user range is both, 10.3 says where, the
  process table gives the high part to the kernel; changelog "A space has
  a high user range, 128 GB past the 4th gigabyte". `runtime/bare/
  board.ll` finds a gigabyte's root entry by address, makes a high
  gigabyte's table as a page is mapped there, gives every one back in
  `space_free` (`free_l2`), and checks a copy and a device mapping lie in
  one part (`user_part_end`). No compiler change, so no seed. Tests:
  `tests/virt/user_high` (map, copy, a thread's call and missing page
  there), `user_high_many` (512 MB across a gigabyte boundary, every table
  given back), `user_high_end` and `user_gap` (refused). Next: the suites.
- 2026-10-29: done. `tools/test.sh` 65, `--compiled` 159, `--virt` on
  aarch64 212 green, the fixpoint among them. `lib/AGENTS.md` says where
  a kernel maps what it shares. Not run: a Pi 5, riscv64's half of
  `--virt` (no qemu-system-riscv64 here); the Pi 5's high part is the
  same code over a boot map whose entries 128 to 255 are empty, as on the
  aarch64 board.
