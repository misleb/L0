# 0073: an exit that works under the hypervisor

Kind: language
Status: proposed
Needs: 0072

## Why

[0068](0068-route-to-bare-metal.md) found emulation about 24 times slower
than native: the compiler compiles itself in 5.07 s against 0.21 s. Under
Apple's hypervisor (`-accel hvf -cpu host`) the image boots and prints, but
QEMU does not handle the semihosting call it stops with, so it never
stops, and standard error, also semihosting, is lost.

Only worth doing if 0072 finds the suite too slow under emulation. If it
does not, this item is dropped with that measurement as the reason.

## Done when

- an image stops with its exit status, and keeps standard error apart,
  under both emulation and the hypervisor, by a channel real hardware could
  also have
- `tools/test.sh --virt` uses the hypervisor where the host has one, and
  its time is recorded against 0072's

## Log

- 2026-10-08: opened by 0068's recommendation, item 5, conditional on 0072.
