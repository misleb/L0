# 0079: a timer deadline, interrupts, and waiting for one

Kind: language
Status: proposed
Needs: 0078

## Why

[0074](0074-route-to-a-microkernel.md)'s item 4. Not ready: its program is
to come from 0078. Under 0078's kernel in L0, `tests/virt/proc/preempted.l0`
cannot pass, since `spin.l0`, beside it, never gives the processor back
and nothing in L0 can take it: there is no timer deadline, and no
interrupt reaches `user_run`. When that kernel runs two processes, that
failure, quoted, is this item's Why.

## The design, as decided

0074's Log, "what a second board costs": the host file owns the interrupt
controller, behind builtins for enabling an interrupt by number, waiting
for one and getting its number, and acknowledging it, and the GIC's
distributor and CPU interface leave `host-virt.ll`'s regions. The timer's
deadline is a system register, and so a builtin.

## Done when

- to be written when the Why is

## Log

- 2026-10-09: opened by 0078, at the user's choice to take user mode
  first.
