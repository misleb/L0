# 0107: slicing and joining bytes

Kind: language
Status: done, changelog "Bytes are sliced and joined without a list"
Needs: nothing

## Why

L0S's request, `probes/bytes/REQUEST-bytes-slice-join.md` in L0S: a
spec 6.6 `bytes` value can be made only by `bytes_from_list`, a read, or
a receive, so nothing gives part of one, or two as one. Wherever a header
and a body must become one message, L0S sends the body through a list, a
cons cell a byte, and back: a spawn's header in front of a program image,
hundreds of KB, and the kernel's writes, fs replies, inet packets, and
NIC frames, each up to 4 KB, on every message. Joining a 6-byte header to
a 512 KB image that way takes 4.4 to 4.9 ms on the host, by L0S's
measurement, and more under TCG.

`roadmap/0107/why.l0`, cut down from L0S's `want.l0`:

```
(def msg_payload ((b bytes)) bytes
  (bytes_slice b 4 (bytes_len b)))

(def write_request ((h (list int)) (written bytes)) bytes
  (bytes_concat (cons (bytes_from_list (append "write " (append h " ")))
                      (cons written (nil bytes)))))
```

```
roadmap/0107/why.l0:7:3: error: unknown function bytes_slice
roadmap/0107/why.l0:10:3: error: unknown function bytes_concat
```

## Done when

- spec 6 and 6.6 give `(bytes_slice b i j)` and `(bytes_concat bs)`;
  section 8 gives the slice's range error; 10.3 declares both and lists
  them as reading their arguments without consuming them, with a result
  that is new rather than a part, so a parameter they read stays
  read-only; the changelog says why
- the checker knows both, with arity and type errors in
  `tests/compiler/check_errors`; the emitter borrows their arguments and
  takes no reference to their result
- `runtime/l0rt.ll` defines `@l0_bytes_slice` and `@l0_bytes_concat`
- behaviour in `tests/unit/bytes_test.l0`, the range error in
  `tests/io`, and a read-only parameter with no counting or leak in
  `tests/io`
- `tools/test.sh`, `--compiled`, `--virt`, and `tools/linux-test.sh`
  green; the seed refreshed, so `tools/l0` knows both
- L0S told

## Log

- 2026-10-24: opened from L0S's request, at the user's request, and
  started. Both borrow, as `write_bytes` does, and return a new value, as
  `bytes_from_list` does.
- 2026-10-24: implemented. Suites 65 and 155 green, here and on Linux
  arm64; the virt suite 336 passed, its two failures `examples_check`
  reading a name clash mid-run, since fixed and passing on both boards.
  Fixpoint holds and the seed is refreshed, so `tools/l0` runs
  `why.l0`. The `l0-code` skill and the examples show both. Committed
  with the seed, at the user's request, and L0S told. Done.
