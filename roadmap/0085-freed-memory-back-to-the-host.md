# 0085: freed blocks go back to the host, a chunk at a time

Kind: language
Status: done, changelog "Freed blocks go back to the host, a chunk at a
time"; passed on Linux arm64
Needs: nothing

## Why

Every cons cell and data block came from a bump arena that took 64 MB
chunks from `l0_host_alloc` and never gave one back, and a freed block
went on a free list for its exact size, which only a block of that size
could take (spec 10.3, "puts them on free lists by size, which allocation
takes from before its arena"). So memory a program freed was neither
returned to the host nor usable at any other size. Arrays and bytes were
the exception: they come from `l0_host_alloc` and go back with
`l0_host_free`.

On a host with an operating system this costs resident memory that never
falls. Where the heap is fixed it costs the program: a process's heap is
380 MiB, so a program that holds 100 MiB of blocks of one size, frees it,
and does the same at three other sizes runs out, though it never holds
more than 100 MiB (`tests/virt/reclaim.l0`, before its array was added):

```
(def sums () (list int)
  (let a (list_sum (list_of 4369066 (nil int)) 0)
    (let b (c2_sum (c2_of 3276800 (C2End)) 0)
      (let c (c3_sum (c3_of 2621440 (C3End)) 0)
        (let d (c4_sum (c4_of 2184533 (C4End)) 0)
          (cons a (cons b (cons c (cons d (nil int))))))))))
```

```
$ tools/test.sh --virt pages
FAIL virt-proc/pages: stdout differs
FAIL virt-user/pages: stdout differs
$ cat build/test-tmp/run.err
l0: runtime error: heap exhausted
```

It passed on the board, whose heap is 1 GiB, and on macOS. A kernel is
the program this goal is for, and one that frees a process's lists and
then needs an array for the next had no way to get that memory back.

## The plan, as built

Blocks are cut from chunks of 1 MiB less 64 bytes, aligned to 1 MiB, from
a new host function, `l0_host_alloc_aligned`. Allocation and freeing are
the old free lists by size, unchanged. A sweep tallies the free lists'
bytes chunk by chunk, takes off the blocks of every chunk whose blocks are
all free, other than the one being cut, and gives those chunks back. It
runs as a chunk is made, once a quarter of the chunks' size has been made
since the last, and whenever the host refuses an allocation, before it is
asked again.

- spec 10.3: the allocation paragraph, the host function, `L0_RC_CHECK`
- runtime: `l0rt.ll`'s chunks and sweep, and every host allocation
  through a wrapper that sweeps and retries; `host-libc.ll` over
  `posix_memalign`; `freestanding.ll`'s aligned allocation
- tests: `tests/virt/reclaim`, which failed as a process before and passes
  under both kernels
- measured: the compiler compiling itself, and the test's phases

No compiled code changes, so no seed refresh is needed: the host
interface is the host's to change (l0-bootstrap, "The host interface is
not the seed's to pin"), and nothing compiled code calls is renamed.

## Done when

- the checklist in the `l0-bootstrap` skill
- `tests/virt/reclaim` passes on the board and under both kernels
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green
- the compiler compiling itself no slower than 5%, and no larger at peak

## Log

- 2026-10-15: opened at the user's request, after reading why freed
  memory never reaches the host, and started. The test written and shown
  to fail as a process under both kernels with the old runtime.
- 2026-10-15: pages of one size with their own lists and counts, the
  first plan, were 15-20% slower on the compiler; so were three variants
  of them and a count per 1 MiB chunk beside the old lists. A count on the
  hot path is the cost (changelog, "Why nothing is counted"). Built
  instead: chunks with no counts, and a sweep that tallies the free lists.
  The test's 300 MiB array first failed as a process because 1 MiB
  chunks in `freestanding.ll` lay 2 MiB apart and a small block landed in
  a gap; chunks of 1 MiB less 64 bytes lie end to end. Compiler: same
  output, cycles within 0.5%, 3.7% more instructions, peak +16 KB.
  Reclaim test passes on the board and under both kernels. Next: full
  suites, `--virt`, Linux arm64.
- 2026-10-15: suites green: 65, 143, `--virt` 132 from 129 (`reclaim` on
  the board and under both kernels); Linux arm64 65 and 143. No seed
  refresh: compiled code and the `l0_` interface are unchanged. Done.
