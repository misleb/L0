# 0086: freeing spaces and frames, and unmapping a page

Kind: language
Status: done, changelog "Freeing spaces and frames, and unmapping a
page"; passed on Linux arm64
Needs: 0078

## Why

L0S, the kernel's own project, asked for it in
`probes/free/REQUEST-free-frames-and-spaces.md` there. Section 6.13 says
"Nothing frees either yet, so a space or frame lasts until the program
ends", and `host-virt.ll` hands both out by bumping: frames from the bottom
of the pool, page tables from the top, and spaces from a counter that stops
at 255. A kernel whose processes come and go cannot give any of it back
(`roadmap/0086/why.l0`):

```
(def release ((s int) (fs (list int))) int
  (let r (space_free s)
    (free_all fs)))

(def revoke ((s int) (va int)) int
  (space_unmap s va))
```

```
$ tools/l0check lib/prelude.l0 lib/io.l0 roadmap/0086/why.l0
roadmap/0086/why.l0:7:10: error: unknown function space_free
roadmap/0086/why.l0:11:30: error: unknown function frame_free
roadmap/0086/why.l0:14:3: error: unknown function space_unmap
```

L0S works around it by keeping each ended process's space whole, with its
frames still mapped, and zeroing it for the next process. That cannot be
done for a space that mapped a device or shared pages, which the next
process would reach. So each driver, window manager, or terminal that ends
uses up one of the board's 255 spaces for good. L0S's
`probes/free/free_virt_test.l0` shows the 255th spawn refused with -5 while
only pid 1 is alive. The request left `space_unmap` for later; the user
asked for it in this item too, so a kernel can take back shared memory,
and drop pages, from a process that is still running.

## The plan

- spec 6.13: `(space_free s)`, `(frame_free f)`, `(space_unmap s va)`; the
  runtime errors `frame still mapped` and `user page not mapped`; numbers
  given again, and that a space's or frame's number then names the new
  one. Section 8's table; 9.2's hosts without user mode; 10.3's calls, host
  functions, codes 9 and 10, and the board's pool with free pages
- changelog: why, why an error for freeing a mapped frame, why frames
  outlive the spaces that map them, why `space_unmap` frees no table
- compiler: the names, arities, calls, and `declare`s
- runtime: `l0rt.ll`'s three calls; `host-virt.ll`'s pool of pages with a
  state per page (free, table, or a frame and its mappings) and a free
  list, space slots given again, `ttbr0_el1` back on the boot map before a
  space's tables are freed, and TLB invalidation for an ASID given again
  and a page unmapped; `host-libc.ll` and `host-proc.ll` give 1 and 2
- tests: `check_errors`; `tests/io` for each builtin on a host with no
  such space or frame; `tests/virt/unit` for a remap seen by a thread
  (stale TLB), a space number given again seen by a thread, frames and
  spaces beyond the pool and the 255, and each runtime error

## Done when

- the checklist in the `l0-bootstrap` skill, with the seed refreshed
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green
- 600 spaces made and freed one after another on the board, more than its
  255; L0S's own `free_virt_test.l0` spawning past 255 needs its kernel to
  call the builtins, which is L0S's change to make

## Log

- 2026-10-15: opened from L0S's request, with `space_unmap` added at the
  user's request, and started.
- 2026-10-15: implemented as planned. `tests/virt/unit/free_test.l0`, 13
  tests, passes on the board, among them 600 spaces in a row. Taking the
  `tlbi` out of `space_unmap` made its remap test read the old frame;
  taking it out of `space_free` changed nothing on QEMU, which appears to
  flush on an ASID change, so the changelog says the flush rests on the
  architecture there. Suites green: 65, 146 from 143, `--virt` 136 from
  132; Linux arm64 65 and 146; seed refreshed, fixpoint holds. Done.
