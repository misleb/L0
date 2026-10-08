# 0066: reading at most n bytes

Kind: language
Status: done, changelog "Reading at most n bytes"; passed on Linux arm64
Needs: 0060

## Why

[0055](0055-programs-round-three.md)'s failure worker could read a byte at a
time or everything at once, and nothing between:

```
(def copy ((f IoFile) (out IoFile)) int
  (match (file_read_some f 65536)
    ((IoReadFailed code) code)
    ((IoBytes b)
      (if (eq (bytes_len b) 0)
          0
          (let w (file_write_bytes out b 0 (bytes_len b))
            (copy f out))))))
```

```
$ tools/l0check lib/prelude.l0 lib/io.l0 roadmap/0055/failure/hypothetical/01-bounded-read.l0
roadmap/0055/failure/hypothetical/01-bounded-read.l0:9:10: error: unknown function file_read_some
roadmap/0055/failure/hypothetical/01-bounded-read.l0:19:9: error: an argument of lt must be int, but this is (IoDone WriteFault)
```

The second error is the hypothetical's `main`, written before 0062 typed
`file_flush`; the first is the limit.

[0060](0060-bounded-reads-and-updatable-bytes.md) measured what that costs:
0055's tee, a byte at a time through the wrappers, takes about 1.04 s of
user time on 100 MB to four outputs, and the same outputs written in blocks
from a whole input 0.24 s, against the system's 0.16 s; but holding the
whole input is 103 MB, and the unpacker holds a whole archive, 28 times
`tar`'s memory.

## Done when

- the spec has `(read_some h n)` as 0060's finding sketches it: the next
  bytes, at least one and at most `n`, waiting only while none has arrived;
  empty at end of input or on a failure, which `read_from` then tells apart;
  what `n` below 1 does decided; 10.3 has the runtime function; the
  changelog says why fresh bytes rather than a read into a buffer, and why
  bytes stay immutable
- the library's `file_read_some f n` gives `IoBytes`, empty at the end, or
  `IoReadFailed`; documented, and shown in the examples
- tests: chunks of every size against a file and an in-memory handle, end
  of input, a failed read, a handle not open for reading, and a copy of a
  large file in constant memory; stage 0 is not extended
- 0055's tee, from `roadmap/0062/tee/`, moved onto it and measured against
  0060's 1.04 s; its unpacker streaming in two passes, measured for memory
- the l0-bootstrap checklist, the seed refreshed, and a Linux run

## Log

- 2026-10-08: proposed by 0060.
- 2026-10-08: done.
  - spec 6.6: `(read_some h n)`, at least one byte and at most `n`, no
    promise to fill; empty at the end, on a failure, or if not open for
    reading, then `read_from` says which; `n` below 1 is the new runtime
    error `byte count out of range` (section 8's table). The table in 6 and
    10.3 name it, and 10.3 says a piece is at most the buffer's 65,536
    bytes
  - runtime: `@l0_read_some`, from what the handle holds back after one
    `read` into an empty buffer, or the next cells of a handle over a list
  - **`@l0_write_bytes` copies blocks** into a descriptor's buffer, where
    it called `@l0_write_to` once per byte. Found by measuring: tee moved
    onto `file_read_some` was only 0.55 s, against 0.27 s for a bare copy
    of the same writes, since whether LTO inlined the per-byte call
    differed between programs. The bytes and their order are unchanged
  - compiler: `read_some` among the bytes builtins, a runtime call, result
    `bytes`; one step, and the seed refreshed
  - library: `file_read_some`; `lib/examples.l0`'s `copy_in_pieces`, with
    a test of 200,000 bytes; the shipped skill's "Reading in pieces"
  - tests: `tests/unit/read_some_test.l0` (8 tests), `tests/io/read_some`
    (a file in pieces of 1,000 and of a hundred million, a pipe, a
    directory as standard input, under `L0_RC_CHECK`), two cases in
    `check_errors`; `bundle_prelude`, `emit_tail`, and `libdoc` re-pinned
    for the declaration and the entry
  - **tee**, from `roadmap/0062/tee/`, moved onto it and kept in
    `roadmap/0066/tee/`: the per-byte loop and its named workaround go, a
    piece goes to each output with one `file_write_bytes`, and outputs are
    still flushed once per 65,536 bytes, which its own tests require (7
    pass). 100 MB to standard output and three files: 0.08 s of real time,
    no measurable user time, 2 MB, every output identical, against 1.02 s
    of user time for 0062's and 0.15 s real for the system's tee
  - **not done: the unpacker in two passes.** Streaming its archive means
    rewriting its parser over pieces, which tests the program rather than
    `read_some`; tee already shows a stream copied in constant memory. The
    unpacker stays as 0062 left it, holding its archive
  - both suites green (65, 131); fixpoint at 1,275,881 bytes, seed
    refreshed and reproduces itself; `tools/linux-test.sh arm64` green
    (65, 131)
