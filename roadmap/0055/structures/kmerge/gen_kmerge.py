"""Inputs for kmerge at 1,000,000 elements, under the directory given.

  words.K   10 sorted files of 100,000 random words each
  nums.K    10 numerically sorted files of 100,000 random integers each
  words.all 1,000,000 unsorted words from a vocabulary of 300,000
  nums.all  1,000,000 unsorted integers below 500,000
"""
import os
import random
import sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rng = random.Random(55)
letters = "abcdefghijklmnopqrstuvwxyz"


def word():
    return "".join(rng.choice(letters) for _ in range(rng.randint(6, 14)))


for k in range(10):
    ws = sorted(word() for _ in range(100_000))
    with open(os.path.join(out, f"words.{k}"), "w") as f:
        f.write("\n".join(ws) + "\n")
    ns = sorted(rng.randint(-10**9, 10**9) for _ in range(100_000))
    with open(os.path.join(out, f"nums.{k}"), "w") as f:
        f.write("\n".join(map(str, ns)) + "\n")

vocab = [word() for _ in range(300_000)]
with open(os.path.join(out, "words.all"), "w") as f:
    f.write("\n".join(rng.choice(vocab) for _ in range(1_000_000)) + "\n")
with open(os.path.join(out, "nums.all"), "w") as f:
    f.write("\n".join(str(rng.randrange(500_000)) for _ in range(1_000_000)) + "\n")
