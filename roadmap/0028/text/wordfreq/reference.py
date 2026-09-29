#!/usr/bin/env python3
"""The same report as wordfreq: reference.py [N] < text."""
import collections
import re
import sys

data = sys.stdin.buffer.read()
counts = collections.Counter(w.lower() for w in re.findall(rb"[A-Za-z]+", data))
ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
if len(sys.argv) > 1:
    ranked = ranked[: int(sys.argv[1])]
out = sys.stdout.buffer
for w, c in ranked:
    out.write(w + b" " + str(c).encode() + b"\n")
