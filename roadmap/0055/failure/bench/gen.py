"""Write 1,000 files totalling 100,000,000 bytes under bench/data/, the same on every run.

Usage: python3 gen.py DIR
"""
import os
import random
import sys

def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    rng = random.Random(55)
    total = 100_000_000
    n = 1000
    weights = [rng.random() + 0.05 for _ in range(n)]
    s = sum(weights)
    sizes = [int(total * w / s) for w in weights]
    sizes[-1] += total - sum(sizes)
    for i, size in enumerate(sizes):
        with open(os.path.join(out, "f%04d.bin" % i), "wb") as f:
            f.write(rng.randbytes(size))
    print("wrote", n, "files,", sum(sizes), "bytes")

main()
