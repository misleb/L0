# kv: a persistent key-value store

**Status: done, with a named workaround.** The plain one-file store works, and
at 100,000 keys each operation takes about a tenth of a second. That is
usable one call at a time, but linear in the store's size. The sharded store
is the workaround.

```sh
tools/l0 build programs/kvstore/kv.l0 programs/kvstore/main.l0 -o kv      # one file
tools/l0 build programs/kvstore/kv.l0 programs/kvstore/sharded.l0 -o kvs  # 256 files
kv FILE get KEY          # prints the value; exit 1 if absent
kv FILE set KEY VALUE    # add or replace
kv FILE del KEY          # remove; exit 1 if absent
tools/l0 test programs/kvstore/kv.l0 programs/kvstore/kv_test.l0
```

Exit status 2 is a usage or I/O error. A missing FILE is an empty store. The
format is one `KEY\tVALUE\n` line per entry, with backslash, tab, and newline
escaped. So any bytes can be a key or value, and a key's line is the one that
starts with its escaped form and a tab. `get` streams the file and stops at
the match. `set` and `del` read every line, then write them all back.

## Files

- `kv.l0`: format, updates, line reading, sharding, and commands (230 lines)
- `main.l0`: the one-file store, `(run 0)`
- `sharded.l0`: the 256-bucket store, `(run 256)`
- `kv_test.l0`: 19 tests
- `gen_store.py`: writes a store of N keys in either layout

## Results

- `tools/l0 test`: 19 passed, 0 failed. The tests cover escaping, including a
  round-trip property over 500 random byte strings; replacing in place,
  appending, and removing; and the hash agreeing with `gen_store.py`. A model
  test runs 2,000 random sets and deletes against a separately written
  list-of-pairs model. File tests exercise store, load, set, and del on disk.
- Every test also passes under `L0_RC_CHECK` with no runtime report.
- Mutation check: dropping the backslash from the newline escape fails 2
  tests.

Timings at 100,000 keys (2.9 MB), measured one process per operation. A loop
of 200 operations includes about 5 ms per operation of process start, which
`/usr/bin/true` also takes:

| operation | one file | 256 buckets |
| --- | --- | --- |
| get, first key | under 10 ms | under 10 ms |
| get, last key or missing | 90 ms | under 10 ms |
| get, mean over 200 spread keys | 50 ms | 8 ms (3 ms above spawn) |
| set or del | 160 ms, 79 MB peak | 8 ms (3 ms above spawn) |

One-file `set` is linear in the store: 22 ms at 10,000 keys, 87 ms at
50,000, 175 ms at 100,000, and 348 ms at 200,000, about 1.7 µs per stored
key. **Loading 100,000 keys one `kv set` at a time would therefore take
about 2.4 hours**, and the 100,000-key stores above were written by
`gen_store.py`. The sharded store would load them in about 13 minutes,
nearly all of it process start.

## What L0 cost here

- **Limit 02, the one that decides the design.** L0 can read a file only
  from its start and can open one for writing only by emptying it. There is
  no append, no seek, and no rename. So:
  - every write costs the whole file
  - an append-only log, an on-disk hash table, and a sorted file with an
    index are all impossible
  - a crash between `open_out` and `file_close` loses the store. Crash
    safety is impossible, not merely costly: writing a temporary file and
    renaming it into place is the standard fix, and there is no rename.
- **The workaround** is `sharded.l0`: the key's hash picks one of 256 files,
  `FILE.0` to `FILE.255`, so a write rewrites about 1/256 of the data. This
  cost 25 lines (`store_path`, `bucket_of`, `hash_onto`, and a bucket-count
  parameter on `run`). It is 20 times faster at 100,000 keys, but still
  linear, only with a smaller constant. It leaves 256 files that kv cannot
  delete or list, since L0 has neither operation. And it is no safer: a crash
  still loses a bucket.
- **Limit 07**: `lib/io.l0` loses failure detail.
  - To treat a missing store as empty, kv compares the `IoFailed` message
    with the words `"no such file"`.
  - `file_read_line` reports a failed read as the end of the file, and a
    store rewritten after such a read would silently lose every later entry.
    kv has its own line reader over `file_read_byte` instead, about 40 lines.
- **Limit 03**: `Updated`, `Lookup`, `Line`, `Lines`, and `Scan` are five
  single-use result types, each an Option or Result of something.
- No function values: `run` takes a bucket count rather than the function
  that maps a key to a path. That was cheap here.
- No clock, so every timing comes from outside the program.
