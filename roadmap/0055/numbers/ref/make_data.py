"""Writes data/big.bin, 100 MB of pseudo-random bytes from a fixed seed."""
import os
import random

here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, "..", "data", "big.bin")
rng = random.Random(55)
with open(path, "wb") as f:
    for _ in range(100):
        f.write(rng.randbytes(1_000_000))
print(path)
