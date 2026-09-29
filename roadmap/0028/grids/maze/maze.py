"""Maze generator and reference BFS, for comparing with the L0 program.

    python3 maze.py gen W H SEED [LOOPS] > maze.txt
    python3 maze.py solve maze.txt

gen carves a perfect maze by randomized depth-first search on the odd
cells, then knocks out a LOOPS fraction (default 0.05) of the remaining
inner walls so there are many paths and BFS has to find the shortest. S is
top left and E bottom right. solve prints the shortest path length, or
"no path", using a flat list and collections.deque.
"""
import collections
import random
import sys


def gen(w, h, seed, loops):
    rnd = random.Random(seed)
    g = [bytearray(b"#" * w) for _ in range(h)]
    cw, ch = (w - 1) // 2, (h - 1) // 2
    seen = bytearray(cw * ch)
    stack = [(0, 0)]
    seen[0] = 1
    g[1][1] = ord(".")
    while stack:
        cx, cy = stack[-1]
        opts = [(cx + dx, cy + dy, dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= cx + dx < cw and 0 <= cy + dy < ch and not seen[(cy + dy) * cw + cx + dx]]
        if not opts:
            stack.pop()
            continue
        nx, ny, dx, dy = rnd.choice(opts)
        seen[ny * cw + nx] = 1
        g[2 * cy + 1 + dy][2 * cx + 1 + dx] = ord(".")
        g[2 * ny + 1][2 * nx + 1] = ord(".")
        stack.append((nx, ny))
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if g[y][x] == ord("#") and rnd.random() < loops:
                g[y][x] = ord(".")
    g[1][1] = ord("S")
    g[2 * ch - 1][2 * cw - 1] = ord("E")
    out = sys.stdout.buffer
    for row in g:
        out.write(bytes(row) + b"\n")


def solve(path):
    rows = [r.rstrip(b"\r\n") for r in open(path, "rb")]
    rows = [r for r in rows if r]
    h, w = len(rows), len(rows[0])
    cells = b"".join(rows)
    s, e = cells.index(b"S"), cells.index(b"E")
    dist = [-1] * (w * h)
    dist[s] = 0
    q = collections.deque([s])
    while q:
        u = q.popleft()
        if u == e:
            print(dist[u])
            return
        x = u % w
        for v, ok in ((u - w, u >= w), (u + 1, x != w - 1), (u + w, u + w < w * h), (u - 1, x != 0)):
            if ok and cells[v] != 35 and dist[v] < 0:
                dist[v] = dist[u] + 1
                q.append(v)
    print("no path")


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        loops = float(sys.argv[5]) if len(sys.argv) > 5 else 0.05
        gen(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), loops)
    else:
        solve(sys.argv[2])
