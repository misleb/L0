"""A trace of requests with skewed keys, one per line, for lru.

  gen_trace.py OUT [N] [KEYS] [S]

N requests (1,000,000) over KEYS distinct keys (1,000,000), drawn from a
Zipf distribution with exponent S (0.9): key rank r has weight 1 / r**S.
Ranks are shuffled onto key numbers so popular keys are not small numbers.
"""
import itertools
import random
import sys

out = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 1_000_000
keys = int(sys.argv[3]) if len(sys.argv) > 3 else 1_000_000
s = float(sys.argv[4]) if len(sys.argv) > 4 else 0.9

rng = random.Random(55)
cum = list(itertools.accumulate(1.0 / (r ** s) for r in range(1, keys + 1)))
names = list(range(keys))
rng.shuffle(names)
picks = rng.choices(names, cum_weights=cum, k=n)
with open(out, "w") as f:
    f.write("\n".join(map(str, picks)) + "\n")
