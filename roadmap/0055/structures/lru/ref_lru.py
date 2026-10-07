"""The reference for lru: the same trace through an OrderedDict.

  ref_lru.py [-s] CAPACITY < TRACE
"""
import sys
from collections import OrderedDict


def main(argv):
    strings = argv[:1] == ["-s"]
    cap = int(argv[1] if strings else argv[0])
    cache = OrderedDict()
    hits = misses = 0
    for line in sys.stdin.buffer:
        k = line.rstrip(b"\n") if strings else int(line)
        if k in cache:
            cache.move_to_end(k)
            hits += 1
        else:
            misses += 1
            if cap <= 0:
                continue
            if len(cache) >= cap:
                cache.popitem(last=False)
            cache[k] = len(line) if strings else line
    print(f"hits {hits} misses {misses} cached {len(cache)}")


main(sys.argv[1:])
