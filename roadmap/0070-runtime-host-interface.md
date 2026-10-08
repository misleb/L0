# 0070: the runtime calls a host interface, with libc behind it

Kind: language
Status: done, changelog "The runtime reaches its host through an interface
of its own"
Needs: 0069

## Why

[0068](0068-route-to-bare-metal.md)'s prototype supplies the 30 libc
functions `runtime/l0rt.ll` declares, and works only by steering the
runtime into fallbacks written for other reasons:

```llvm
define i32 @pthread_create(ptr %t, ptr %a, ptr %f, ptr %arg) {
entry:
  ret i32 11      ; fails, so l0rt.ll's main runs the program on its own stack
}

define ptr @dlsym(ptr %h, ptr %name) {
entry:
  ret ptr null    ; finds nothing, so errno reads as -1
}
```

`dup` returns 3 so that the standard descriptors look open, and `getrlimit`
reports the boot stack. A change to any of those paths in `l0rt.ll`, made
for macOS or Linux, would break the board, and no host test would notice.
This makes the board harder to get wrong: `l0rt.ll` calls a small interface
of its own, which this item names in section 10.3 (0069 left it unnamed,
since nothing implemented it), and `runtime/host-libc.ll` implements it
with libc.

## Done when

- the checklist in the `l0-bootstrap` skill
- `l0rt.ll` calls libc nowhere; `runtime/host-libc.ll` is the only file
  that does, and `tools/build.sh`, `tools/install.sh`, and `tools/l0` link
  both
- every program's output, errors, and exit status are unchanged: both
  suites green, the fixpoint holds, Linux arm64 green
- section 10.3 names the interface, and every function in it has an
  answer a host without an operating system can give, as section 9.2
  says: a file operation that fails as an empty file system does, a large
  stack that may be refused, no `dlsym` and no descriptor numbers in it

## Log

- 2026-10-08: opened by 0068's recommendation, item 2.
- 2026-10-08: done. Spec 10.3 names 14 `l0_host_` functions, whose
  failures are 6.3 codes, and `@l0_rt_run(size)`, which the host's entry
  point calls on a stack of that size. `runtime/host-libc.ll` holds
  everything that touched libc, moved unchanged but for returning codes:
  errno by `dlsym`, the `access` and `opendir` probes, `fopen` for
  appending, SIGPIPE, the standard descriptors, the 512 MB thread, and
  `main`. `l0rt.ll` calls only the interface, `memcmp`, and LLVM
  intrinsics. The tools link two objects, `l0rt.o` and `l0host.o`
  (`L0_HOST` overrides the second), since merging them would need
  `llvm-link`. `tests/io/host_boundary` checks the boundary, and flags 29
  libc declarations in the old `l0rt.ll`. No compiler change, so no seed
  refresh. Both suites green (65, and 132 compiled), fixpoint holds, Linux
  arm64 green (65 and 132). The seed compiles the compiler in 0.20 s,
  against 0.21 s before, with byte-identical output.
  `roadmap/0068/metal.ll` no longer links with `l0rt.ll`; 0071 replaces it.
