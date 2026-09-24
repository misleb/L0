#!/usr/bin/env python3
"""Writes a kv store of N keys, for timing programs/kvstore.

Usage:
  gen_store.py N FILE            one-file store, the format main.l0 uses
  gen_store.py N FILE BUCKETS    bucketed store, the format sharded.l0 uses

Keys are key0000000 .. and values value-<i>-<i*7919 mod 100003>, so a
test can recompute any value. Loading 100000 keys through kv set instead
would take N rewrites of a growing file, which is the cost being measured.
"""
import sys


def key(i):
    return "key%07d" % i


def value(i):
    return "value-%d-%d" % (i, i * 7919 % 100003)


def bucket_of(k, buckets):
    # Must match bucket_of in sharded.l0.
    h = 0
    for c in k.encode():
        h = (h * 31 + c) % 1000003
    return h % buckets


def main():
    n = int(sys.argv[1])
    path = sys.argv[2]
    if len(sys.argv) == 3:
        with open(path, "w") as f:
            for i in range(n):
                f.write("%s\t%s\n" % (key(i), value(i)))
        return
    buckets = int(sys.argv[3])
    files = [[] for _ in range(buckets)]
    for i in range(n):
        files[bucket_of(key(i), buckets)].append("%s\t%s\n" % (key(i), value(i)))
    for b, lines in enumerate(files):
        with open("%s.%d" % (path, b), "w") as f:
            f.writelines(lines)


main()
