# 0060: research: reading at most n bytes, and bytes that update in place

Kind: research
Status: done; a bounded read returning fresh bytes (0066); bytes that update
in place wait
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
- 2026-10-08: **finding.** Measured in the main tree on 0055's 100 MB file,
  user time unless said, programs in `tmp/0060/`.
  - **The two limits are two changes, and only one is earned now.**
  - **The sieve no longer needs bytes that update.** 0058's bit builtins
    make the bitset sieve to 10^8 (`sieve_bits.l0`, 5,761,455 primes) 0.57 s
    of real time in 14 MB. That beats the byte-per-flag sieve 0055 wanted on
    both counts, and Python's bytearray, 0.42 s in 295 MB by slices or 3.06 s
    in 115 MB by index. The 802 MB was the cost of a flag per word, which the
    bitset never paid
  - **Reading is where the cost is.** One output, a byte at a time with
    `read_byte` and `write_byte` (0055's `limits/01-bounded-read-bytecat`),
    takes 0.14 s in 1.6 MB; the whole input at once (`-wholecat`) 0.07 s in
    103 MB. A bounded read gives the second's speed in the first's memory.
    For `tee`, four outputs: written a byte at a time through the wrappers,
    0055's tee takes about 1.04 s; written as four `write_bytes` of a whole
    input (`tee_whole.l0`), 0.24 s, against the system's 0.16 s, nearly all
    of it in the system. So block reads take tee to within about 1.5 times
    of the system's, from 6.5. The unpacker can stream too: check every
    checksum in one bounded pass and write in a second, rather than hold
    the whole archive, 28 times `tar`'s memory
  - **Fresh bytes, not a read into a buffer.** A read into bytes the
    program passes in would save one allocation per chunk, about 1,600 for
    100 MB in 64 KB chunks, which is nothing beside the reads themselves,
    and would need bytes that update in place first. A read returning fresh
    bytes needs nothing else: `bytes` stay immutable, reference counting
    frees each chunk when its last use ends, and the result has the type a
    program already handles
  - **Semantics, for the language item.** `(read_some h n)` returns the
    next bytes on `h`, at least one and at most `n`, waiting only while
    none has arrived, as `read(2)` does, after delivering standard output
    and error as any wait does (6.3); empty bytes at end of input, or if
    the read failed or `h` is not open for reading, after which `read_from`
    says which, as after `read_bytes` (6.6). It takes what the handle has
    buffered first. What `n` below 1 does, an error or empty bytes, is the
    item's to decide. The library wraps it as `file_read_some`, giving
    `IoBytes`, whose empty bytes mean the end, and `IoReadFailed`
  - **Bytes that update in place**, by `bytes_new` and `bytes_set` under
    `array_set`'s rule: the runtime's copy-when-shared is `array_set`'s, but
    the emitter's in-place forms and the read-only analysis would take
    `bytes_set` as they take `array_set`, and spec 6.6's "nothing changes a
    bytes value" goes. No program here needs them once the sieve is a
    bitset: building bytes from a list (`bytes_from_list`, 24 bytes a byte
    while the list lives) appears in tests and in small conversions, never
    at a size that cost anything measured. A packed `(array T)` for small
    element types has less evidence still
  - **The `IoFile` wrappers.** Their 2.1 to 2.8 times in a per-byte loop
    (0063) stops mattering where a program reads in chunks: a wrapper call
    per 64 KB is free
  - **Recommendation.**
    1. [0066](0066-bounded-read.md), language: `read_some` and the library's
       `file_read_some`, with 0055's `hypothetical/01-bounded-read.l0` as
       its Why; 0055's tee moved onto it and measured against the 1.04 s
       above, and its unpacker streaming in two passes. The compiler and the
       prelude use none of it
    2. bytes that update in place wait for a program that builds bytes at
       a size that costs something, or reads into a buffer at a rate where
       the allocation shows; `limits/04-no-mutable-bytes.l0` and its
       hypothetical are what they would replace
