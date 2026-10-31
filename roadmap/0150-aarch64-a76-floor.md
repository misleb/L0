# 0150: the aarch64 targets assume a Cortex-A76, and QEMU emulates one

Kind: tooling
Status: done, changelog "The aarch64 targets assume a Cortex-A76, and no language change for it"
Needs: 0148

## Why

0148's `bytes_dot_i8` is portable vector IR, and on aarch64 LLVM lowers
it to `smull` and `saddw`, eight instructions per sixteen bytes. The
Pi 5's Cortex-A76 has `sdot`, sixteen int8 multiply-adds into four i32
lanes in one instruction, but LLVM emits it only when told the CPU has
it, and the aarch64 manifests named no CPU, while the virt board ran
QEMU as a Cortex-A72, which lacks it. So the instruction the Pi 5 would
run was not the one the virt suite tested.

Read from `clang --target=aarch64-none-elf -S`, with the loop at 64
bytes a step and one reduction per step:

| Target | Inner loop per 64 bytes |
| --- | --- |
| aarch64, `-mcpu=cortex-a76` | 4 `sdot`, 1 `add`, 1 `addv` |
| aarch64, no CPU named | 4 `smull`, 4 `smull2`, 7 adds, 1 `addv` |
| x86_64 | 8 `pmaddwd`, 9 `paddd` |
| riscv64 | compiles, scalar |

That shape stays one runtime text for every host; only a target's flags
decide whether `sdot` is used. LLVM's partial-reduction intrinsic, which
reaches `sdot` with one reduction at the end, was not taken: the riscv64
backend refuses it, so it cannot be in the shared runtime.

## The decision

The three aarch64 targets, the virt board, the Pi 5, and a process of a
kernel, name `cortex-a76` to clang, and the virt board's QEMU emulates
one, so the suite runs the instructions the Pi 5 runs. The floor is per
target, as every flag in a manifest is: a board with an older core, such
as a Pi 4's Cortex-A72, would bring its own manifest and its own CPU, and
the runtime is correct on it unchanged, since nothing in it is written
for one CPU.

## Done when

- the three manifests name the CPU, and `virt-aarch64.target`'s QEMU
  arguments say `-cpu cortex-a76`
- `runtime/l0rt.ll`'s `bytes_dot_i8` takes 64 bytes a step with one
  reduction, and its comment says why
- `spec/boards/virt-aarch64.md`, `pi5.md`, and `process.md` say which
  CPU each target assumes; the changelog says why, and that it is no
  language change
- `tools/test.sh`, `--compiled`, and `--virt` green on both boards; the
  host probe measured again
- `roadmap/l0s-adoption.md` §14's line about `sdot` says what is now
  true

## Log

- 2026-10-31: opened at the user's request, with 0148 and 0149 committed
  as 6fecb07; the Pi 5 run is skipped for now, by the user's choice, so
  L0S is not kept waiting on it.
- 2026-10-31: the manifests, the loop, the board pages, the changelog,
  and the adoption guide done. The host probe, L0S's `dot.l0` with
  `bytes_dot_i8` a row: 71 ps per multiply-add, from 140 with the lane
  accumulator and 1898 before 0148, the same checksum; the host object
  has the eight `pmaddwd`. Suites and `--virt` running.
- 2026-10-31: done. The virt board's `l0rt.bc`, compiled with the
  manifest's `-mcpu=cortex-a76` as `tools/l0` compiles it, has four
  `sdot` in `l0_bytes_dot_i8`, and none without the flag. `tools/test.sh`
  74, `--compiled` 179, `--virt` 427 passed on both boards, the aarch64
  one as a Cortex-A76. The compiler is unchanged, so the seed is as
  6fecb07 left it. Not run on a Pi 5, by the user's choice, nor on macOS.
