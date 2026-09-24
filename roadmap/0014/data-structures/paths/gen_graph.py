#!/usr/bin/env python3
"""Writes a random graph and queries for programs/paths, or their answers.

Usage:
  gen_graph.py NODES EDGES QUERIES SEED > input.txt
  gen_graph.py NODES EDGES QUERIES SEED --answers > expected.txt

Node names are n0 .. n{NODES-1}; weights are 1 to 1000. All edges come
first, then the queries, so every query sees the whole graph. The answers
come from heapq Dijkstra, independent of the L0 program.
"""
import heapq
import random
import sys


def build(nodes, edges, queries, seed):
    rng = random.Random(seed)
    es = [(rng.randrange(nodes), rng.randrange(nodes), rng.randint(1, 1000))
          for _ in range(edges)]
    qs = [(rng.randrange(nodes), rng.randrange(nodes)) for _ in range(queries)]
    return es, qs


def dijkstra(adj, src, dst):
    if src == dst:
        return 0
    dist = {src: 0}
    heap = [(0, src)]
    while heap:
        d, u = heapq.heappop(heap)
        if u == dst:
            return d
        if d > dist.get(u, float("inf")):
            continue
        for v, w in adj.get(u, ()):
            nd = d + w
            if nd < dist.get(v, float("inf")):
                dist[v] = nd
                heapq.heappush(heap, (nd, v))
    return None


def main():
    nodes, edges, queries, seed = (int(a) for a in sys.argv[1:5])
    es, qs = build(nodes, edges, queries, seed)
    out = sys.stdout
    if "--answers" in sys.argv:
        adj = {}
        for a, b, w in es:
            adj.setdefault(a, []).append((b, w))
        for a, b in qs:
            d = dijkstra(adj, a, b)
            out.write("unreachable\n" if d is None else "%d\n" % d)
        return
    for a, b, w in es:
        out.write("n%d n%d %d\n" % (a, b, w))
    for a, b in qs:
        out.write("n%d n%d\n" % (a, b))


main()
