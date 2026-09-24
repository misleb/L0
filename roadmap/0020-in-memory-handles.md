# 0020: Handles that read from and write to memory

Kind: language
Status: queued
Needs: 0019

## Why

From [0014](0014-programs-round-two.md). L0 has no function values, so code
that reads a stream cannot take its byte source as an argument, and the only
way to test it on a string is through a file.

- `0014/text-tools/limits/02-no-byte-source-argument.l0`: checker output
  `error: from_stdin is a function, and L0 has no function values`. To be
  testable on strings, csvcol's parser became a pure (state, byte) to state
  function, 4 times slower than a direct parser (1.07 s against 0.27 s), and
  wordfreq's tokenizer is written twice.
- `0014/bytes-encodings/limits/05-no-in-memory-streams.l0`: 68 lines of
  temporary-file setup in base64's and minigrep's tests.

Both workers proposed a handle that reads from a list of bytes and one that
collects what is written to it, rather than function values.

## Done when

The l0-bootstrap checklist, plus csvcol's direct parser tested on strings
through the new handles.

## Log

- 2026-09-24: opened from 0014.
