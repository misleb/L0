# 0020: Handles that read from and write to memory

Kind: language
Status: done, changelog "Handles that read from and write to memory"
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
- 2026-09-25: done. `open_bytes`, `open_buffer`, and `buffer_bytes`, wrapped
  in `lib/io.l0` as `open_in_bytes`, `open_out_buffer`, and
  `buffer_contents`. `tests/unit/csvcol.l0` is csvcol's direct parser over
  handles, and `csvcol_test.l0` runs 0014's cases on it through strings: 0.34
  s on the 14.5 MB file against the step function's 1.00 s, same output as
  Python. wordfreq's second tokenizer and base64's file plumbing were not
  rewritten; they are 0014 evidence, and the tests here show the pattern.
  The I/O gaps from 0014 are closed; next is 0021.
