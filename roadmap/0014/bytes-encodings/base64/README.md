# base64

`base64` encodes standard input to standard output as RFC 4648 base64, 76
characters to a line. `base64 -d` decodes, ignoring whitespace, accepting
input with or without padding, and rejecting anything else with a message
and exit status 1. Both stream a byte at a time, in constant memory.

```sh
export L0_COMPILER=$PWD/build/l0c-native L0_RUNTIME=$PWD/build/l0rt.o
tools/l0 build programs/base64/base64.l0 programs/base64/base64_main.l0 -o /tmp/base64
tools/l0 test programs/base64/base64.l0 programs/base64/base64_test.l0
programs/base64/bench.sh 10
```

`main` is in its own file because `l0 test` supplies a `main` of its own.

## Status: done

- **Tests:** 18 of 18 pass, and also pass under `L0_RC_CHECK=1`. They cover
  the RFC 4648 test vectors both ways, line wrapping at 57 and 58 input
  bytes, whitespace, unpadded input, five kinds of bad input, and two
  properties: 100 random binary inputs of up to 300 bytes round trip
  exactly, and encoded output uses only the alphabet, padding, and lines of
  at most 76 characters.
- **Round trip:** byte-exact on 10 MB of `/dev/urandom`. The encoding is
  identical to the system `base64` apart from line breaks, and the system
  `base64 -d` decodes it. 100 KB and 3 MB round trips under `L0_RC_CHECK=1`
  report no leak and no use after free.
- **Throughput** on 10 MB, best of three, Apple M4 Pro:

  | | time | peak memory |
  | --- | --- | --- |
  | l0 encode | 0.06 s (170 MB/s) | 1.5 MB |
  | l0 decode | 0.14 s (13.5 MB in) | 1.6 MB |
  | system encode | 0.01 s | 1.2 MB |
  | system decode | 0.16 s | 1.2 MB |

  The first run of a freshly linked binary took 0.53 s to encode. That is
  macOS checking a new binary on first launch, not L0, and it is why
  `bench.sh` takes the best of three.

## What L0 made hard

**A lost write to standard output cannot be detected (limit 01).** With
standard output closed, `base64 < 10MB >&-` exits 0 having written nothing.
The system `base64` prints `base64: write error` and exits 1. `write_to`
reports success because the byte is only buffered, and the failure could
only be reported by `close`, which refuses handle 1. Nothing a program can
call ever sees it. No workaround exists. See `programs/limits/01-*`.

**Testing streaming code needs real files (limit 05).** `encode` and
`decode` take handles, and there is no handle over a string in memory, so
the tests write each input to `/tmp`, run the code between two files, and
read the output back. That took 42 nonblank lines of plumbing before the
first test, and the tests need a writable `/tmp`. See `programs/limits/05-*`.

## What was not a limit

L0 has no bitwise operators. Splitting three bytes into four 6-bit values is
`(div b0 4)`, `(add (mul (mod b0 4) 16) (div b1 16))`, and so on, which is
exact because bytes are never negative. It reads less directly than shifts
and masks, but it cost no measurable time: decode is as fast as the system's.

The alphabet is a chain of range tests rather than a table. With four ranges
and two single characters that is short, and needs no array.
