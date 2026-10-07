"""The reference for kmerge: the same commands and output, in Python.

  ref_kmerge.py merge|distinct [-n] FILE...
  ref_kmerge.py bench heap|set N
"""
import heapq
import sys


def lines(path, numeric):
    with open(path, "rb") as f:
        for line in f:
            s = line.rstrip(b"\n")
            yield int(s) if numeric else s


def show(x):
    return str(x).encode() if isinstance(x, int) else x


def main(argv):
    out = sys.stdout.buffer
    mode = argv[0]
    if mode == "bench":
        which, n = argv[1], int(argv[2])
        x = 1
        xs = []
        for _ in range(n):
            xs.append(x)
            x = (x * 1103515245 + 12345) % 2147483648
        if which == "heap":
            h = []
            for i, v in enumerate(xs):
                heapq.heappush(h, (v, i))
            last, bad = -1, 0
            while h:
                v, _ = heapq.heappop(h)
                bad += v < last
                last = v
            print("heap out-of-order", bad, n)
        else:
            s = set(v % 1000000000 for v in xs)
            size = len(s)
            for v in xs[: n // 2]:
                s.discard(v % 1000000000)
            ordered = sorted(s)  # what an ordered set would give
            print("set size, after removing half", size, len(ordered))
        return 0
    numeric = argv[1:2] == ["-n"]
    paths = argv[2:] if numeric else argv[1:]
    if mode == "merge":
        it = heapq.merge(*(lines(p, numeric) for p in paths))
    else:
        seen = set()
        for p in paths:
            seen.update(lines(p, numeric))
        it = sorted(seen)
    out.writelines(show(x) + b"\n" for x in it)
    return 0


sys.exit(main(sys.argv[1:]))
