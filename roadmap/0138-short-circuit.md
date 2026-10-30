# 0138: and and or evaluate their second operand only when it matters

Kind: language
Status: done
Needs: nothing

## Why

`and` and `or` are strict (spec 6, section 8), so `(and (not (is_empty
xs)) (gt (head xs) 0))` still calls `head` on the empty list, and the
l0-code skills tell the writer to use nested `if` instead. The trap caught
the compiler itself: the lexer's `(and (not (is_empty rest)) (is_name_rest
(head rest)))` crashed on a source file ending in a digit (changelog, "A
declaration's miscounted parens are counted", *Also fixed*). Strictness
buys nothing a program can want. The smallest program that cannot be
written as it reads: the test above.

## The rule

`(and a b)` evaluates `b` only when `a` is `true`, and `(or a b)` only when
`a` is `false`. This changes behaviour only where `b` fails or has an effect
and `a` decides, which code written to the skills never relies on.
`tests/lang/err_and_strict.l0` pins the strict reading and would be
re-blessed; the frozen stage-0 oracle keeps the strict reading, so that
test leaves the differential suite, as tests of every feature after stage 0
do. Emission is the `if` the writer would have written.

## Done when

- the checklist in the l0-bootstrap skill
- spec 6's table and section 8 state the rule, and 8's "every `and` and
  `or` operand is evaluated" goes
- a test of each builtin's short circuit, with an effect in the second
  operand, in `tests/io`; `err_and_strict` re-blessed or removed
- the skills' paragraph on strict `and` and `or` says the opposite
- `roadmap/l0s-adoption.md` says what changes for a program that relied
  on both operands being evaluated, with a grep for a second operand that
  has an effect

## Log

- 2026-10-30: opened, from the review (its item 1.4); proposed.
- 2026-10-30: done. Spec 6's table, section 8, and 10.3's emission note
  say the rule; the emitter emits a builtin `and` or `or` as the `if` it
  means, with the second operand outside tail position, so tail-call
  components are unchanged. `tests/lang/err_and_strict` is gone from the
  differential suite, since stage 0 keeps the strict reading;
  `tests/io/and_or_short` writes a byte in each second operand, and
  `tests/unit/order_test` now expects the two writes the first operands
  decide away to be skipped. Both skills say the opposite of what they
  did. No L0S second operand has an effect, by the guide's grep. Both
  suites, the fixpoint, and `--virt` on both boards green. No language
  item remains in the queue but 0130, left by the user's choice.
