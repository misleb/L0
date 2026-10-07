"""Writes N random calculator expressions, one per line, from a fixed seed.
Usage: gen_exprs.py N MAXINT > file"""
import random
import sys

n, maxint = int(sys.argv[1]), int(sys.argv[2])
rng = random.Random(55)


def expr(depth):
    if depth == 0 or rng.random() < 0.3:
        v = str(rng.randint(0, maxint))
        return ("-" + v) if rng.random() < 0.1 else v
    parts = [expr(depth - 1)]
    for _ in range(rng.randint(1, 3)):
        parts.append(rng.choice("+-*/"))
        parts.append(expr(depth - 1))
    s = " ".join(parts)
    return "(" + s + ")" if rng.random() < 0.5 else s


out = sys.stdout
for _ in range(n):
    out.write(expr(4) + "\n")
