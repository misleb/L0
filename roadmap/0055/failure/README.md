# 0055, tools that handle failure

Three programs: an archiver, a log rotator, and a `tee`. Each one says which
operation failed, on which file, and why. They were written from the shipped
guide and nothing else: `lib/AGENTS.md`, `lib/skills/l0-code/SKILL.md`,
`spec/L0.md` (sections 1 to 9 and 11 in full, which is what `l0 spec --path`
names), `l0 doc`, `l0 doc io`, and `lib/examples.l0` with
`lib/examples_test.l0`. I did not read the compiler, the runtime, stage 0, or
the test suites.

Every program checks with `l0 check`, and its tests pass under `l0 test`:
archive 22/22, rotate 9/9, tee 7/7.

## Layout

```
archive/   archive.l0 archive_test.l0 main.l0     pack OUT FILE... / unpack ARCHIVE DIR
rotate/    rotate.l0 rotate_test.l0 main.l0       rotate LOG N [--stop-after K]
           interrupt.py   interrupts it at every step and every pair of steps, and by SIGKILL
           rotate_ref.py  the same algorithm in Python, as the reference
tee/       tee.l0 tee_test.l0 main.l0             tee [-a] FILE...
bench/     gen.py (1,000 files, 100,000,000 bytes, seeded), verify.py (checks an
           archive with zlib.adler32, independently of the L0 code), bench.py
           (median of runs under /usr/bin/time -l), corrupt.py
exp/       e1-e3.l0: where tee's time goes
limits/    the smallest program for each limit
hypothetical/  the code I would have written, which does not compile
```

The large inputs and outputs have been deleted. `python3
tmp/0055/failure/bench/gen.py tmp/0055/failure/bench/data` regenerates them.

## Results

All runs are on this Mac with a warm cache. Each time is the median of 3 to 5
runs.

| program | L0 lines (+ tests) | L0 time | L0 peak RSS | reference | ref time | ref peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| pack 1,000 files, 100 MB | 423 (+150), shared with unpack | 0.55 s | 3.5 MB | `tar -cf` | 1.52 s | 3.9 MB |
| unpack the same | (same file) | 0.43 s | **104.0 MB** | `tar -xf` | 1.59 s | 3.7 MB |
| rotate, N = 1000 | 216 (+65) | 0.31 s | 1.8 MB | Python, same algorithm and journal (34 lines) | 0.37 s | 15.5 MB |
| tee 100 MB to stdout and 3 files | 202 (+102) | **1.14 s** | 1.9 MB | `/usr/bin/tee` | 0.16 s | 1.2 MB |
| (tee, written with the documented `IoFile` wrappers) | | 2.91 s | 1.9 MB | | | |

`verify.py` checks the L0 archive against zlib. `diff -r` and `cmp` show that
unpack and tee reproduce their inputs byte for byte. tar stores more per file
than the L0 archive does (mode, owner, times, 512-byte blocks), so the
archiver timing is not like for like. L0 cannot read any of that metadata
(limit 05).

### Archiver

The format is an 8-byte magic, a count with its own Adler-32, and then, for
each entry, the name length, the data length, an Adler-32 of those two
lengths, an Adler-32 of the name followed by the data, the name, and the
data. An 8-byte end marker closes it. `unpack` reads and checks the whole
archive before it writes anything. Tests show that it refuses every prefix
and every single changed byte of a sample archive, and it never crashes on
one. On the 100 MB archive:

```
unpack: refusing corrupt.l0ar: it is corrupt: entry 496 (…/f0495.bin) does not match its checksum; nothing was written
unpack: refusing trunc.l0ar: it is truncated: entry 496 needs 145600 bytes and 103895 remain; nothing was written
pack: cannot open …/missing.txt to read: no such file
pack: cannot open …/secret.txt to read: permission denied
pack: cannot open …/in to read: input or output failed            (a directory)
pack: /etc/hosts: the name is an absolute path
pack: writing the archive while adding …/f0017.bin: input or output failed   (a full 2 MB volume)
pack: …/big.l0ar.partial is left behind incomplete, since L0 cannot delete a file
pack: cannot create …/nodir/x.l0ar.partial: input or output failed (its directory …/nodir does not exist, and L0 cannot create one)
unpack: cannot create …/ro/AGENTS.md: input or output failed      (a read-only directory)
unpack: cannot create …/out2/AGENTS.md: permission denied         (an existing read-only file)
unpack: …/a.txt: it is a file, not a directory; nothing was written
```

The checksum is Adler-32 because it needs only `add` and `mod`, and CRC-32
would need `xor`. That costs nothing: Adler-32 in L0 sums 10 MB in 15 ms,
faster than the builtin `hash` takes over the same bytes (19 ms).

### Rotator

`rotate LOG N` takes N + 1 steps. It renames LOG.N-1 to LOG.N, and so on down
to LOG to LOG.1, then creates LOG with `open_appending`, so it never empties a
log that a writer has just recreated. A rename whose source is missing (-3)
is skipped. Before each step it records the step in `LOG.rotating`, and it
writes that journal under another name and renames it into place. A run that
finds a journal naming a step finishes that rotation instead of starting a
new one.

**How I know it is safe if interrupted.** `interrupt.py` sets up seven file
sets: N = 1, 3, and 5, with gaps, with no LOG, and with files beyond N. For
each set it stops the rotator before every rename or create (the
`--stop-after K` hook, status 3), and before every pair of them, once while
rotating and again while finishing. That is 536 interrupted runs. After each
interruption it checks three things. Every file holds exactly one original's
contents, or nothing (the new LOG). No original is in two files. Nothing is
lost except the old LOG.N, after LOG.N-1 has replaced it. Then it runs the
rotator again and compares the result with an uninterrupted rotation. It also
kills a 200-file rotation with SIGKILL at a random moment in its first 30 ms,
200 times, with no hook, and checks the same things. The result is 0
failures. Repeating a step after a crash is harmless because a repeated step
finds its source already moved and skips it. The one state the hook does not
produce is a crash after a journal's temporary file is written but before it
is renamed. That state only adds a stale `LOG.rotating.tmp`, which the next
`open_out` empties.

Rename failures, each provoked for real:

```
rotate: renaming …/log.2 to …/log.3: input or output failed           (log.3 is a non-empty directory)
rotate: stopped before step 1 of 4; every file is whole, and running rotate again finishes the rotation from there
rotate:   not done: rename …/log.2 to …/log.3
rotate:   not done: rename …/log.1 to …/log.2   … and the rest
rotate: renaming …/log.1 to …/log.2: input or output failed           (chflags uchg log.1, mid-rotation)
rotate: finishing an interrupted rotation of …/log from step 2 of 4   (after chflags nouchg: correct result)
rotate: recording step 1: cannot create …/log.rotating.tmp: input or output failed   (read-only directory)
```

The rotator stops at the first failed rename. Going on would rename a file
over the one that failed to move, and that file's contents would be lost.

### tee

tee goes on when an output fails. At the end it reports every output, if any
of them failed, and exits 1. Here are real failures, with 10 MB in:

```
tee: standard output: written in full, 9880237 bytes
tee: …/good.txt: written in full, 9880237 bytes
tee: …/in: failed on open: input or output failed                 (a directory)
tee: …/ro/x.txt: failed on open: input or output failed           (a read-only directory)
tee: …/teemnt/full.bin: failed on write, found by a flush after 917504 bytes: input or output failed   (1 MB volume)
tee: …/nodir/x.txt: failed on open: input or output failed        (a missing directory)
tee: …/teemnt/small.bin: failed on flush: input or output failed  (60 KB into 8 KB free)
tee: …/out2/AGENTS.md: failed on open: permission denied          (-a onto a read-only file)
```

I could not provoke "failed on close", a close that fails after its flush
succeeded, on a local disk. The unit tests reach the write and flush cases in
memory by giving tee a handle that is open only for reading as an output.
Every write to it is then lost.

Writes are held back, so "failed on write" can only mean that a flush made
while copying found lost bytes. tee flushes every output once per 65,536
bytes and closes the ones that fail.

Two outputs could not be handled at all. Both are limits 06 and 07 below. A
pipe whose reader exits kills tee with status 141, nothing said, and its
other files cut short (196,608 of 9,880,237 bytes). If standard output is
closed (`>&-`), the first file opened becomes standard output, so the file
holds every byte twice, and tee reports success. BSD tee does the same.

## Limits, ranked by cost

### 1. A read of at most n bytes (limits/01-bounded-read-*.l0, hypothetical/01-bounded-read.l0)

What could not be written: a streaming copy in blocks, `(file_read_some f
65536)`. `l0 check` on the hypothetical says `error: unknown function
file_read_some`. A program can read one byte at a time, or with `read_bytes`
or `file_read_all` all of what is left, and nothing in between.

Measured on 100 MB:

| | time | peak RSS |
| --- | --- | --- |
| `cat` | 0.01 s | 1.9 MB |
| L0 byte loop, `read_byte`/`write_byte` (streams) | 0.18 s | 1.6 MB |
| L0 `read_input` + `file_write_bytes` (blocks, holds it all) | 0.10 s | 102.7 MB |
| L0 tee, byte loop, 4 outputs | 1.14 s | 1.9 MB |
| system tee | 0.16 s | 1.2 MB |

What it costs the programs:
- tee runs 7 times slower than the system tee.
- unpack holds the whole archive: 104 MB against tar's 3.7 MB, 28 times
  more. Streaming unpack byte by byte would be cheap (0.18 s per 100 MB), but
  then it could check a checksum only after writing the file, and limit 03
  means it could not remove a file that failed the check. Holding the archive
  is the price of "nothing was written" on a corrupt archive.
- pack holds each input whole, since a file's size is known only by reading
  it (limit 05).

### 2. A broken pipe kills the program (limits/06-sigpipe.l0, 06b, 06c)

What could not be written: a tee that goes on to its files after standard
output's reader exits. There is no workaround in L0. Observed:

- `06-sigpipe | head -c 10` and `06b`: the failing flush does return -5, and
  the message is printed (`flush failed after 196608 bytes`), but the process
  exits with status **141**, not the 3 that `main` returned. Spec 6.3 says "A
  program that has been told of every failure keeps the status it returned".
- `06c` and tee: these go on after the failed flush, writing to stderr and
  opening a file. They are killed with 141 before anything more happens. The
  stderr line written just after the failed flush is lost, and the file is
  never created. tee's other file stops at 196,608 bytes. Spec 6.3 says held
  back output "is delivered when the program ends, normally or with a runtime
  error". Spec section 8 lists every way a program can end, and a signal is
  not among them.

This is a correctness failure with no workaround. It is not a performance
cost. I did not characterize it further, because that needs the runtime.

### 3. Rename, flush, and close failures are integers, and every open fault but three is OpenFailed or CreateFailed (limits/02-io-codes.l0, 02b-unchecked.l0, hypothetical/02-typed-faults.l0)

What could not be written: any message more specific than "input or output
failed". `02-io-codes` prints `CreateFailed, input or output failed` for
creating in a read-only directory (host: EACCES), in a missing directory
(ENOENT), and on a directory (EISDIR). It prints `-5, input or output failed`
for renaming over a non-empty directory (EISDIR) and out of a read-only
directory (EACCES). A full disk reaches tee and pack as the same -5. Spec 6.3
keeps -4 for an existing file that may not be written, so a new file in a
read-only directory is -5.

Nothing forces the checks. `02b-unchecked.l0` ignores a failed `rename_file`,
checks, and exits 0 without a word. The host catches only an unreported
*write* failure, as status 70. The typed version, `RenameFault` / `CloseFault`
with cases for missing, denied, is-a-directory, cross-device, no space, and
broken pipe, gets `error: the subject of a match must be a data type, but this
is int` from `l0 check`.

Cost: the WORKAROUND in archive.l0 is about 25 lines (`dir_problem`,
`parent_note`, `parent_of`). It opens the parent to read and turns
`OpenMissing` into "its directory does not exist". It cannot tell a read-only
directory from any other failure, and it misreads two cases (limit 05). The
write, flush, and close cases tee reports are told apart by *when* the
failure showed, not by anything the host said.

### 4. The documented IoFile wrappers in a loop that runs once per byte (exp/e1.l0, e2.l0, e3.l0)

On 100 MB to standard output and three files:

| variant | time |
| --- | --- |
| list of `IoFile` with `file_read_byte`/`file_write_byte`, as the skill says | 2.03 s |
| `(array IoFile)` with the wrappers | 1.49 s |
| `(array int)` of raw handles with `read_from`/`write_to` | 0.76 s |

`IoFile` is a data value, so every `array_get` of one, and every match the
wrapper makes, costs reference counting. The skill says only an int or bool
element is free. tee's hot loop is the named WORKAROUND, raw handles in an
`(array int)`, which brought tee from 2.91 s to 1.14 s at the cost of about
15 lines. The skill's "Use the wrappers ... not the raw builtins" costs 2.7
times here.

### 5. No delete (limits/03-delete.l0, hypothetical/03-delete.l0)

`(remove_file path)` gets `error: unknown function remove_file`. Because of
this, a failed pack leaves `OUT.partial`, and unpack leaves a file it could
not finish. The rotator keeps `LOG.rotating` (saying `idle`) forever, and it
cannot drop LOG.N+1 and older left by an earlier, larger N; it names each
one instead. The cost is files left behind, not time.

### 6. No directories: create or list (limits/04-directories.l0, hypothetical/04-directories.l0)

`(make_dir ...)` gets `error: unknown function make_dir`. Because of this:
- Unpacking the benchmark archive needed `mkdir -p
  DIR/tmp/0055/failure/bench/data` first. Without it, all 1,000 entries fail
  with "its directory ... does not exist, and L0 cannot create one".
- pack cannot take a directory. The shell's glob named the 1,000 files.
- The rotator finds files beyond N by probing LOG.N+1, LOG.N+2, ... with
  `open_in`, and misses any file past a gap.

### 7. No metadata: kind, size, mode, times (limits/05-metadata.l0, hypothetical/05-metadata.l0)

The probe in limit 3 assumes that `OpenFailed` means "a directory". Worse,
the implementation reports a self-referential symlink (ELOOP) and a name of
more than 255 bytes (ENAMETOOLONG) as **OpenMissing, "no such file"**, so
the probe says such a directory does not exist (`05-metadata` prints
`missing`). The archive cannot keep a file's mode or times, and a file's size
is known only by reading all of it.

### 8. Closed standard handles are reused (limits/07-closed-stdout.l0)

Run with `>&-`, `07-closed-stdout OUT` puts both lines in OUT, and every flush
and close returns 0. Spec 6.3 says "Three are open from the start". The spec
says nothing about the host making that true. GNU coreutils reopens
/dev/null in this case.

### 9. Hashing part of a bytes value (limits/08-hash-range.l0)

This costs nothing here. `hash` takes only a whole value, and nothing slices
bytes, so hashing one entry of an archive held as bytes means copying it
through a list. On 10 MB that took 72 ms and 250 MB of peak RSS. Adler-32 in
L0 took 15 ms with no copy, so the archiver uses it.

### Not limits

- Binary integers in the format: `u64_bytes` and `get_u64` are 10 lines each,
  using `div` and `mod`.
- Exit status: `main`'s result works, apart from limit 2.
- Telling a missing rename source from other failures: -3 is enough for the
  rotator to skip gaps.

## The spec, skill, and docs

1. **Implementation against spec 6.3.** `open_in` gives OpenMissing ("no
   such file") for ELOOP and ENAMETOOLONG. The spec keeps -3 for a file that
   does not exist and gives -5 for any other failure.
2. **Implementation against spec 6.3.** After a reported flush failure on a
   broken pipe, the exit status is 141, not what `main` returned. A program
   that goes on after that failure is killed, and its held-back output is lost
   (limit 2). The spec says nothing about signals at all.
3. **Spec 6.3 is silent** on a program started with handle 0, 1, or 2 closed
   (limit 8).
4. **Spec 6.3 and `l0 doc CreateFault`** are consistent, but they make
   creating a file in a read-only directory "input or output failed", where
   the host said permission denied. `CreateDenied` reads as if it covered that
   case. The doc should say that it does not.
5. **SKILL.md, "Files and arguments"**: "Use the wrappers l0 doc io lists, not
   the raw builtins". In a loop that runs once per byte, the wrappers cost 2.7
   times (limit 4). The memory section's "free to call" list should say that
   an `(array IoFile)` or a list of them is not free.
6. **SKILL.md** says `file_flush` and `file_close` are "the only place such a
   failure shows". That is accurate, but it means "failed on write" cannot be
   reported apart from "failed on flush". The task's own wording assumed it
   could be. Worth saying outright.
7. **Diagnostic**: `data` as a parameter name (it is reserved, and the spec's
   list says so) gives `a parameter name must be lowercase and not reserved`
   and then `a data declaration needs an uppercase type name` at the type. The
   second error is noise.
