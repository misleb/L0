# 0099: a process's runtime hands free heap pages back to its kernel

Kind: language
Status: done, changelog "A process hands free heap pages back to its
kernel"; passed on Linux arm64
Needs: nothing

## Why

L0S, the kernel's own project, asked for it in
`l0-request-heap-pages.md` there. Spec 10.3 lets a kernel map a page of a
process's heap only when it is first touched, and L0S's does, but nothing
ever tells it a page is free again: in a process, `l0_host_free` is
`freestanding.ll`'s allocator over the process's own heap, so 0085's
freed chunks, and every array and bytes value, stop there. A frame the
heap touched once stays the process's until it exits, so a process holds
its peak heap, not what it holds now. That costs nothing for a short
command and the whole board for L0S's servers, which run from boot to
shutdown. The kernel cannot tell a free page from a live one, and a
program cannot reach its allocator, since calls from 256 are the
program's, not the runtime's.

`tests/virt/user/release.l0` holds 32 MiB in an array, lets it go, and
asks the L0 test kernel how many frames it has left before and after.

## The plan

- spec 10.3: call 12, `release(base, len)`, and what a kernel may do on
  it, ignoring it included; which pages the allocator names
- runtime: `freestanding.ll`'s `l0_host_free` names the whole pages of a
  freed block that hold none of its bookkeeping, through a hook its host
  defines: a process's makes call 12, a board's does nothing
- `tests/virt/user/kernel.l0`: answers 12 by unmapping and freeing each
  mapped page in the range, and gives `frame_free_count` by a call of its
  own, 263; the IR harness kernels keep answering 12 as one they do not
  know, which is the other half of what the spec allows
- tests: `tests/virt/user/release`
- measured: the compiler compiling itself as a process, against 0085

No compiled code changes, so no seed refresh: the host interface is the
host's to change.

## Done when

- the checklist in the `l0-bootstrap` skill
- `tests/virt/user/release` fails before and passes after
- `tools/test.sh --virt` and `tools/linux-test.sh arm64` green
- the compiler compiling itself as a process no slower

## Log

- 2026-10-21: opened from L0S's request, and started. `release` written
  first, against kernel.l0's new call 263: 8,212 frames kept on both CPUs.
- 2026-10-21: implemented as planned; the hook is `l0_heap_release`.
  `release` has its frames back on both CPUs. Compiler as a process, at
  HEAD and now: aarch64 8, 8, 9 s and 8, 8, 8 s (board, harness, L0
  kernel); riscv64 10, 10, 11 s and 10, 10, 10 s; same fixpoint. Suites
  green: 65, 149, `--virt` 297 passed, 88 skipped; Linux arm64 65 and 149.
  No seed refresh. Next: tell L0S, whose side is answering call 12.
