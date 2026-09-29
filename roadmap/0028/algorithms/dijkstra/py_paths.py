#!/usr/bin/env python3
"""Python reference for dijkstra: reads the same input from stdin, dict +
heapq, answering each query over the edges read before it."""
import heapq
import sys


def shortest(adj, src, dst):
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
    adj = {}
    out = []
    for line in sys.stdin:
        p = line.split()
        if len(p) == 3:
            adj.setdefault(p[0], []).append((p[1], int(p[2])))
        elif len(p) == 2:
            d = shortest(adj, p[0], p[1])
            out.append("unreachable\n" if d is None else "%d\n" % d)
    sys.stdout.write("".join(out))


main()
