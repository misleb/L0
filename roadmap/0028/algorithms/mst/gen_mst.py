#!/usr/bin/env python3
"""A random connected weighted graph for mst, or its answer from Python.

Usage:
  gen_mst.py NODES EDGES SEED > edges.txt
  gen_mst.py --solve edges.txt          Kruskal in Python: weight and edges

The first NODES-1 edges form a random spanning tree, so the graph is
connected; the rest join random pairs. Weights are 1 to 1,000,000, and the
edges are shuffled.
"""
import random
import sys


def generate(nodes, edges, seed):
    rng = random.Random(seed)
    es = [(i, rng.randrange(i), rng.randint(1, 1000000)) for i in range(1, nodes)]
    while len(es) < edges:
        es.append((rng.randrange(nodes), rng.randrange(nodes), rng.randint(1, 1000000)))
    rng.shuffle(es)
    sys.stdout.write("".join("%d %d %d\n" % e for e in es))


def solve(path):
    fs, ts, ws = [], [], []
    top = -1
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            a, b, w = int(p[0]), int(p[1]), int(p[2])
            fs.append(a); ts.append(b); ws.append(w)
            top = max(top, a, b)
    n = top + 1
    parent = list(range(n))
    rank = [0] * n

    def find(x):
        r = x
        while parent[r] != r:
            r = parent[r]
        while parent[x] != r:
            parent[x], x = r, parent[x]
        return r

    total = count = 0
    for e in sorted(range(len(ws)), key=ws.__getitem__):
        if count >= n - 1:
            break
        ra, rb = find(fs[e]), find(ts[e])
        if ra == rb:
            continue
        if rank[ra] < rank[rb]:
            parent[ra] = rb
        elif rank[ra] > rank[rb]:
            parent[rb] = ra
        else:
            parent[rb] = ra
            rank[ra] += 1
        total += ws[e]
        count += 1
    print("weight %d\nedges %d" % (total, count))


if sys.argv[1] == "--solve":
    solve(sys.argv[2])
else:
    generate(*(int(a) for a in sys.argv[1:4]))
