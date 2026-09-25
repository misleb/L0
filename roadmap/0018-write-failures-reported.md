# 0018: A program can learn that its writes failed

Kind: language
Status: done, changelog "A program can learn that its writes failed"
Needs: 0017

## Why

From [0014](0014-programs-round-two.md), `0014/bytes-encodings/limits/01-stdout-write-failure.l0`,
re-checked in the main tree: with standard output closed, every `write_byte`
returns 0, `(close 1)` returns -2, and the program exits 0 having written
nothing. `write_byte` and `write_to` only buffer, `close` is the only thing
that reports a write failure, and it refuses handles 0 to 2. The system
`base64` in the same situation says "write error" and exits 1. There is no
workaround. The worker's hypothetical is `0014/bytes-encodings/hypothetical/01-stdout-write-failure.l0`,
which adds a `(flush h)` builtin.

Spec 6.3 is also silent on what happens when the final flush of handles 0 to
2 fails at exit; today the exit status is unaffected. This item settles it.

## Done when

The l0-bootstrap checklist, plus a test that closes standard output and sees
the failure reported, on macOS and Linux.

## Log

- 2026-09-24: opened from 0014; first of the I/O gaps, by the user's choice.
- 2026-09-24: done. A `flush` builtin, and a write failure never reported to
  the program is a runtime error at exit (status 70). The reasoning is in the
  changelog entry; `tests/io/write_failure` and `tests/io/result_lost` are the
  checks, green on macOS and Linux. 0014's wordfreq defined its own `flush`
  and was renamed to `flush_word`. The limit program now exits 70 with
  `l0: runtime error: write failed`. Next is 0019.
