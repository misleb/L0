# 0142: the spec's normative lists as tables

Kind: tooling
Status: proposed
Needs: 0141

## Why

The spec is written as long paragraphs with addresses, codes, and
register offsets inline, and tables are the exception. Its stated reader is
an agent that looks things up: the order a builtin's checks run in (6.12,
6.13, 6.15), what each host lacks (9.2), the context layout (10.3), the
system calls, the frame windows, the interrupts. Each of those is a list
or a table written as prose, and some are stated twice in slightly
different words.

## The change

Form, not content: each normative list becomes a table or a numbered list,
one rule per paragraph, done a section at a time after 0141 has placed
them, with the changelog saying nothing changed in meaning. A wording
change that turns out to be a meaning change is a language item of its own.

## Done when

- sections 6.12 to 6.19, 9.2, and 10.3's host interface, boards, and
  process contract are tables and lists where they were paragraphs
- `tests/check`'s `.cerr` files are unchanged, since no message changes
- `roadmap/l0s-adoption.md` notes that nothing changed in meaning

## Log

- 2026-10-30: opened, from the review (its item 2.2); proposed.
