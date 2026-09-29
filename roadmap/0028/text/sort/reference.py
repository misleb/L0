#!/usr/bin/env python3
"""The lines of stdin in bytewise order, as LC_ALL=C sort prints them."""
import sys

data = sys.stdin.buffer.read()
lines = data.split(b"\n")
if data.endswith(b"\n") or not data:
    lines.pop()
lines.sort()
out = sys.stdout.buffer
for line in lines:
    out.write(line + b"\n")
