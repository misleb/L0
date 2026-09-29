"""Reference Life, and a random-board generator, for comparing with the L0 program.

    python3 life.py gen W H SEED > board.txt
    python3 life.py run board.txt GENERATIONS > out.txt

`run` uses plain lists of lists, the way one would write it without numpy.
"""
import random
import sys


def gen(w, h, seed):
    rnd = random.Random(seed)
    out = []
    for _ in range(h):
        out.append("".join("#" if rnd.random() < 0.3 else "." for _ in range(w)))
    sys.stdout.write("\n".join(out) + "\n")


def run(path, n):
    rows = [line.rstrip("\r\n") for line in open(path)]
    rows = [r for r in rows if r]
    g = [[1 if c == "#" else 0 for c in r] for r in rows]
    h, w = len(g), len(g[0])
    for _ in range(n):
        new = []
        for y in range(h):
            up, mid, down = g[(y - 1) % h], g[y], g[(y + 1) % h]
            row = [0] * w
            for x in range(w):
                l, r = (x - 1) % w, (x + 1) % w
                k = up[l] + up[x] + up[r] + mid[l] + mid[r] + down[l] + down[x] + down[r]
                row[x] = 1 if k == 3 or (k == 2 and mid[x]) else 0
            new.append(row)
        g = new
    sys.stdout.write("".join("".join("#" if c else "." for c in r) + "\n" for r in g))


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
    else:
        run(sys.argv[2], int(sys.argv[3]))
