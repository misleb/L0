#!/usr/bin/env python3
"""timeline.py -- feed a program's stdin on a schedule and timestamp its output.

Usage:
    timeline.py [--at SECONDS TEXT]... [--eof SECONDS] -- PROG [ARGS...]

Each --at writes TEXT (with \\n escapes expanded) to PROG's stdin at SECONDS
after start. --eof closes stdin at SECONDS (default: right after the last
--at). Every event -- each write, the close, and each chunk PROG writes to
stdout, as soon as it arrives -- is printed with its time since start, so the
order of input and output in time can be read off directly.

The script exits 0 whatever PROG does; the timeline is the result.
"""
import os
import select
import subprocess
import sys
import time


def main():
    args = sys.argv[1:]
    if "--" not in args:
        sys.exit(__doc__)
    split = args.index("--")
    opts, cmd = args[:split], args[split + 1:]
    writes, eof = [], None
    i = 0
    while i < len(opts):
        if opts[i] == "--at":
            writes.append((float(opts[i + 1]),
                           opts[i + 2].encode().decode("unicode_escape").encode()))
            i += 3
        elif opts[i] == "--eof":
            eof = float(opts[i + 1])
            i += 2
        else:
            sys.exit("unknown option " + opts[i])
    if eof is None:
        eof = max([t for t, _ in writes], default=0.0)
    events = sorted([(t, "write", data) for t, data in writes]) + [(eof, "eof", b"")]
    events.sort(key=lambda e: (e[0], e[1] == "eof"))

    start = time.monotonic()
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, bufsize=0)
    out_fd = proc.stdout.fileno()
    stdin_open = True

    def stamp(what, data=b""):
        print("  t+%5.2fs  %-6s %r" % (time.monotonic() - start, what, data),
              flush=True)

    first_output = None
    while True:
        now = time.monotonic() - start
        while events and events[0][0] <= now:
            _, kind, data = events.pop(0)
            if kind == "write" and stdin_open:
                proc.stdin.write(data)
                proc.stdin.flush()
                stamp("stdin", data)
            elif kind == "eof" and stdin_open:
                proc.stdin.close()
                stdin_open = False
                stamp("eof")
        timeout = max(0.0, events[0][0] - now) if events else 0.5
        ready, _, _ = select.select([out_fd], [], [], timeout)
        if ready:
            chunk = os.read(out_fd, 65536)
            if not chunk:
                break
            if first_output is None:
                first_output = time.monotonic() - start
            stamp("stdout", chunk)
    code = proc.wait()
    err = proc.stderr.read()
    if err:
        stamp("stderr", err)
    stamp("exit", str(code).encode())
    if first_output is None:
        print("no output.")
    else:
        print("first output byte at t+%.2fs." % first_output)


if __name__ == "__main__":
    main()
