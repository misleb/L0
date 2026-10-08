# 0066: reading at most n bytes

Kind: language
Status: proposed
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
