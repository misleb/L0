#!/usr/bin/env python3
"""Writes a CSV file with awkward fields, for checking csvcol against
Python's csv module and timing it.

usage: gen.py ROWS COLUMNS [SEED] > file.csv
"""
import csv
import random
import sys


def field(rng):
    kind = rng.random()
    if kind < 0.5:
        return str(rng.randint(-10**6, 10**6))
    alphabet = "abc xyz,\"\n'\t;"
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 15)))


def main():
    rows, cols = int(sys.argv[1]), int(sys.argv[2])
    rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    w = csv.writer(sys.stdout, lineterminator="\r\n")
    for _ in range(rows):
        w.writerow([field(rng) for _ in range(cols)])


if __name__ == "__main__":
    main()
