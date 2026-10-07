# 0057: the runtime keeps section 6.3's promises

Kind: language
Status: done, changelog "A broken pipe is a write failure, a closed
standard handle is open on nothing, and -3 means nothing is there"; passed
on Linux arm64, amd64 not run
Needs: 0056

## Why

[0055](0055-programs-round-three.md)'s failure worker found three ways the
implementation breaks spec 6.3, each re-checked in the main tree.

**A broken pipe kills the program.** This writes until a flush fails, then
reports it and returns 3:

```
(def loop ((n int)) int
  (let w (write_str "y\n")
    (if (lt (file_flush (IoFile 1)) 0)
        (let e (write_err (append "flush failed after " (append (digits n) " lines\n")))
          3)
        (loop (add n 1)))))

(def main () int (loop 0))
```

```
$ tmp/0055/recheck/sigpipe | head -c 10; echo "status ${pipestatus[1]}"
y
y
y
y
y
flush failed after 863 lines
status 141
```

6.3: "A program that has been told of every failure keeps the status it
returned." It exits 141, by SIGPIPE, and section 8 says nothing of signals.
A program that carries on writing after the failure, as a `tee` must, dies
silently mid-copy, and its other files are left short.

**Two open failures say "no such file".** `(open_read path)` of a link to
itself, and of a name over 255 bytes, returns -3; 6.3 gives -3 to a file
that does not exist, and -5 to any other failure.

**A closed standard handle is reused.** Started with handle 1 closed
(`prog OUT >&-`), the first file opened becomes handle 1, both outputs go
into it, and the program exits 0. 6.3 says the three handles "are open from
the start" and is silent on a host that started the program otherwise.

## Done when

- spec 6.3 or 8 says what a write to a pipe with no reader does (a failure
  of the write, reported as -5 by `flush` and `close`, never a signal), and
  what a program started with handle 0, 1, or 2 closed sees; the changelog
  says why
- the runtime does what the spec says, and the two open failures map to -5
- tests: the pipe program above exits 3 under `head`; the two opens return
  -5; a program started with standard output closed does not write into its
  files. Where the suite cannot set this up, a script under `tests/io/`
  does
- the l0-bootstrap checklist

## Log

- 2026-10-06: queued by 0055, with the user's agreement.
- 2026-10-07: done, but for the Linux run.
  - spec 6.3: a closed standard handle is open on nothing; -3 is for a
    name the host looked up and found nothing at, and a name it cannot
    look up is -5; a write to a pipe with no reader is a write failure,
    never a stop. A directory on the way that may not be searched now gives
    `open_read` -4, where it gave -3
  - runtime: `host_setup`, before the program's thread, ignores SIGPIPE,
    opens `/dev/null` in the other direction on a closed descriptor 0, 1,
    or 2, and finds errno's accessor by `dlsym` (`__error` on macOS,
    `__errno_location` on Linux); `open_handle` and `l0_rename` read errno
    after `access` fails, using only codes numbered alike on both hosts.
    The header's rules say so. No interface in 10.3 changed, so the seed
    did not
  - tests: `tests/io/broken_pipe` (told: exits 3 and writes its file;
    quiet: exits 70), `tests/io/closed_std` (closed standard output and
    input), and `tests/io/open_faults` with a loop, a path through it, a
    300-byte name, a missing directory, a file as a directory, an
    unsearchable directory, and renames of four of them. All three fail on
    the committed runtime and pass on the new one
  - both suites green (63, 118); fixpoint at 1,218,142 bytes, seed up to
    date
  - **owed: `tools/linux-test.sh`**, since Docker was not running. It
    matters here more than usual: `dlopen` and `dlsym` on glibc, `signal`,
    and `/dev/null` on a closed descriptor are all untested on Linux
  - next: the Linux run, then 0058
- 2026-10-07: `tools/linux-test.sh arm64` green: 63 and 118 on Ubuntu
  24.04's clang 18, so `dlsym` finds `__errno_location` in glibc without
  `-ldl`, and the broken pipe, closed handles, and open codes behave as on
  macOS. The container runs as root, so the unsearchable directory is
  skipped there, as the other permission cases are. amd64 was not run, at
  the user's choice, since it takes much longer under emulation. Next: 0058
