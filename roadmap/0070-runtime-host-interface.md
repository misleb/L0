# 0070: the runtime calls a host interface, with libc behind it

Kind: language
Status: queued
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
of its own, the one 0069 names in section 10.3, and `runtime/host-libc.ll`
implements it with libc.

## Done when

- the checklist in the `l0-bootstrap` skill
- `l0rt.ll` calls libc nowhere; `runtime/host-libc.ll` is the only file
  that does, and `tools/build.sh`, `tools/install.sh`, and `tools/l0` link
  both
- every program's output, errors, and exit status are unchanged: both
  suites green, the fixpoint holds, Linux arm64 green
- the interface takes nothing a board cannot give: no threads, no
  `dlsym`, no descriptor numbers beyond the standard three, unless 0069's
  spec says the board has them

## Log

- 2026-10-08: opened by 0068's recommendation, item 2.
