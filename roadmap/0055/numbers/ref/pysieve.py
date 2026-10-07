"""Sieve of Eratosthenes up to N in Python, for comparison with ../sieve.
Usage: pysieve.py slice|loop N
  slice  a bytearray, a byte per flag, crossed off with slice assignment
         (the idiomatic fast Python: the inner loop runs in C)
  loop   the same bytearray, crossed off one index at a time in Python"""
import sys
from math import isqrt


def slice_sieve(n):
    s = bytearray([1]) * (n + 1)
    s[0] = s[1] = 0
    for p in range(2, isqrt(n) + 1):
        if s[p]:
            s[p * p::p] = bytes(len(range(p * p, n + 1, p)))
    return s.count(1), s.rindex(1)


def loop_sieve(n):
    s = bytearray([1]) * (n + 1)
    s[0] = s[1] = 0
    for p in range(2, isqrt(n) + 1):
        if s[p]:
            for j in range(p * p, n + 1, p):
                s[j] = 0
    return s.count(1), s.rindex(1)


def main():
    mode, n = sys.argv[1], int(sys.argv[2])
    count, last = (slice_sieve if mode == "slice" else loop_sieve)(n)
    print("%d primes up to %d, the last %d" % (count, n, last))


main()
