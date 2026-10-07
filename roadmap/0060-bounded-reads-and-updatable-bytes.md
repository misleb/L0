# 0060: research: reading at most n bytes, and bytes that update in place

Kind: research
Status: proposed
Needs: nothing

## Why

[0055](0055-programs-round-three.md) found two limits on bytes, from two
workers. Reading is a byte at a time or all at once:

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
$ tools/l0 check tmp/0055/failure/hypothetical/01-bounded-read.l0
tmp/0055/failure/hypothetical/01-bounded-read.l0:9:10: error: unknown function file_read_some
```

So `tee` is 5.9 times the system's, and unpacking holds the whole archive,
28 times `tar`'s memory. And no bytes can be made or changed except from a
list (`tmp/0055/numbers/limits/04`: `unknown function bytes_set`,
`bytes_new`), so a flag per number costs a word: 802 MB for a sieve to
10^8, against Python's bytearray at 115 MB.

## The question

What gives L0 both, and are they one change or two? Weigh at least:

- a bounded read returning fresh `bytes`, against a read into bytes the
  program passes in, which needs bytes that update in place
- `bytes_new` and `bytes_set` under `array_set`'s rule (spec 6.5), against
  a packed `(array T)` for small element types, against leaving bytes
  immutable
- what each costs the properties the `l0-bootstrap` skill lists, and what
  the library's `IoFile` wrappers become (0055 measured them at 2.7 times
  raw handles in a per-byte loop)

## Done when

- the Log has a finding: each candidate's semantics, implementation, and
  cost, measured against 0055's tee, unpack, and sieve
- a recommendation that names the first language item, with a program from
  this repository as its Why, and the items after it in order

## Log

- 2026-10-06: opened by 0055, with the user's agreement.
