#!/usr/bin/env python3
"""csvcol FILE N with Python's csv module, for comparing outputs."""
import csv
import sys

with open(sys.argv[1], newline="") as f:
    n = int(sys.argv[2])
    for row in csv.reader(f):
        sys.stdout.write((row[n - 1] if n <= len(row) else "") + "\n")
