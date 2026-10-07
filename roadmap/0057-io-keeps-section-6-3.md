# 0057: the runtime keeps section 6.3's promises

Kind: language
Status: queued
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
