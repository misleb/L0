#!/usr/bin/env python3
"""The same report as wordfreq, for comparing outputs on large inputs."""
import collections
import re
import sys

data = sys.stdin.buffer.read()
words = re.findall(rb"[A-Za-z0-9\x80-\xff]+", data)
counts = collections.Counter(w.lower() for w in words)
out = sys.stdout.buffer
for w, c in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
    out.write(w + b" " + str(c).encode() + b"\n")
