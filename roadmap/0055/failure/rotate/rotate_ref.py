"""The reference rotator: the same renames as rotate.l0, in Python, with the
same journal, so the two are timed doing the same work.

Usage: python3 rotate_ref.py LOG N
       python3 rotate_ref.py --setup LOG N    writes LOG and LOG.1 .. LOG.N
"""
import os
import sys

def write_journal(log, text):
    tmp = log + ".rotating.tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.rename(tmp, log + ".rotating")

def rotate(log, n):
    for s in range(n):
        write_journal(log, "rotate %d %d\n" % (n, s))
        src = log if s == n - 1 else "%s.%d" % (log, n - 1 - s)
        try:
            os.rename(src, "%s.%d" % (log, n - s))
        except FileNotFoundError:
            pass
    write_journal(log, "rotate %d %d\n" % (n, n))
    open(log, "a").close()
    write_journal(log, "idle\n")

if sys.argv[1] == "--setup":
    log, n = sys.argv[2], int(sys.argv[3])
    for i in range(n + 1):
        with open(log if i == 0 else "%s.%d" % (log, i), "w") as f:
            f.write("line %d\n" % i)
else:
    rotate(sys.argv[1], int(sys.argv[2]))
