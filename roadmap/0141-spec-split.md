# 0141: the spec split into the language, the runtime, and the boards

Kind: tooling
Status: proposed
Needs: nothing

## Why

`spec/L0.md` is 3,700 lines, of which section 10.3 alone is about 1,250:
the runtime interface, three boards' device tables, GIC and PLIC numbers,
the Pi 5's PCIe window arithmetic and MSI-X offsets, and the ELF loading
contract, in one section. Section 1's list of effects already omits 6.18,
6.19, and `board_reset`, which is what happens when one document carries
three rates of change. The l0-code skill says "read the spec, it is
short"; an agent writing an ordinary program needs sections 1 to 9, about
2,000 lines.

## The split, all of it normative

- `spec/L0.md`: sections 1 to 9, the language a program is written in,
  with 10's interface summarised in a paragraph that points on
- `spec/runtime.md`: 10.1 to 10.4, the contract between the compiler, the
  runtime, and a host
- `spec/boards/virt-aarch64.md`, `virt-riscv64.md`, `pi5.md`, and
  `process.md`: each host's devices, interrupts, layout, and what it lacks
- section 6's table in two groups: every program's builtins, and the host
  facilities a kernel or driver has

Nothing in the language changes. `AGENTS.md`'s invariant becomes "the
files under `spec/` are the only source of truth", `l0 spec --path` names
them all, `tools/install.sh` copies them, and `lib/AGENTS.md` says which to
read for what.

## Done when

- the files exist and every cross-reference between them resolves
- `tools/l0 spec`, `tools/install.sh`, `l0 init`'s AGENTS.md, and the
  skills point at the right file
- `tests/io/libdoc` and anything else reading the spec's path passes
- `roadmap/l0s-adoption.md` says which file L0S's agents read for what,
  and that `l0 spec --path` now names several

## Log

- 2026-10-30: opened, from the review (its item 2.1); proposed.
