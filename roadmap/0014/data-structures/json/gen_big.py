#!/usr/bin/env python3
"""Writes a large JSON document to stdout for timing programs/json.

Usage: gen_big.py N > big.json   (N records; 100000 is about 10 MB)
"""
import json
import random
import sys

n = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
rng = random.Random(1)
records = [
    {
        "id": i,
        "name": "user%d" % i,
        "score": rng.randint(-10**12, 10**12),
        "active": rng.random() < 0.5,
        "tags": ["t%d" % rng.randint(0, 99) for _ in range(rng.randint(0, 4))],
        "note": None if rng.random() < 0.3 else "caf\u00e9 \"quoted\"\n",
    }
    for i in range(n)
]
json.dump(records, sys.stdout, ensure_ascii=True, separators=(",", ":"))
