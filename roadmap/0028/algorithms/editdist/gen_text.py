#!/usr/bin/env python3
"""Two related texts for editdist, or their distance from Python.

Usage:
  gen_text.py BYTES EDITS SEED OUT1 OUT2   random words, then a copy with
                                           EDITS random byte edits
  gen_text.py --solve FILE1 FILE2          two-row DP in pure Python
"""
import random
import sys


def generate(size, edits, seed, out1, out2):
    rng = random.Random(seed)
    words = ["".join(rng.choice("abcdefghijklmnopqrstuvwxyz")
                     for _ in range(rng.randint(1, 9))) for _ in range(500)]
    text = []
    n = 0
    while n < size:
        w = rng.choice(words) + (" " if rng.random() < 0.9 else "\n")
        text.append(w)
        n += len(w)
    a = bytearray("".join(text)[:size], "ascii")
    b = bytearray(a)
    for _ in range(edits):
        k = rng.randrange(3)
        i = rng.randrange(len(b))
        c = ord(rng.choice("abcdefghijklmnopqrstuvwxyz "))
        if k == 0:
            b[i] = c
        elif k == 1:
            del b[i]
        else:
            b.insert(i, c)
    while len(b) < size:
        b.append(ord(rng.choice("abcdefghijklmnopqrstuvwxyz ")))
    b = b[:size]
    open(out1, "wb").write(a)
    open(out2, "wb").write(b)


def solve(p1, p2):
    a = open(p1, "rb").read()
    b = open(p2, "rb").read()
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        ca = a[i - 1]
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j - 1] + (ca != b[j - 1]), prev[j] + 1, cur[j - 1] + 1)
        prev = cur
    print("distance %d" % prev[len(b)])


if sys.argv[1] == "--solve":
    solve(sys.argv[2], sys.argv[3])
else:
    generate(int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5])
