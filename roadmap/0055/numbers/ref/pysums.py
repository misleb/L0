"""CRC-32 and SHA-256 written in pure Python (no zlib, no hashlib), for a
comparison with the L0 program that also computes them by hand.
Usage: pysums.py FILE [MAX_BYTES]"""
import sys

K = [int(x, 16) for x in """
428a2f98 71374491 b5c0fbcf e9b5dba5 3956c25b 59f111f1 923f82a4 ab1c5ed5
d807aa98 12835b01 243185be 550c7dc3 72be5d74 80deb1fe 9bdc06a7 c19bf174
e49b69c1 efbe4786 0fc19dc6 240ca1cc 2de92c6f 4a7484aa 5cb0a9dc 76f988da
983e5152 a831c66d b00327c8 bf597fc7 c6e00bf3 d5a79147 06ca6351 14292967
27b70a85 2e1b2138 4d2c6dfc 53380d13 650a7354 766a0abb 81c2c92e 92722c85
a2bfe8a1 a81a664b c24b8b70 c76c51a3 d192e819 d6990624 f40e3585 106aa070
19a4c116 1e376c08 2748774c 34b0bcb5 391c0cb3 4ed8aa4a 5b9cca4f 682e6ff3
748f82ee 78a5636f 84c87814 8cc70208 90befffa a4506ceb bef9a3f7 c67178f2
""".split()]
H0 = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
M = 0xFFFFFFFF


def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & M


def compress(h, block):
    w = [int.from_bytes(block[i:i + 4], "big") for i in range(0, 64, 4)]
    for t in range(16, 64):
        x, y = w[t - 15], w[t - 2]
        s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
        s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
        w.append((w[t - 16] + s0 + w[t - 7] + s1) & M)
    a, b, c, d, e, f, g, hh = h
    for i in range(64):
        s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        ch = (e & f) ^ (~e & g)
        t1 = (hh + s1 + ch + K[i] + w[i]) & M
        s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        mj = (a & b) ^ (a & c) ^ (b & c)
        hh, g, f, e, d, c, b, a = g, f, e, (d + t1) & M, c, b, a, (t1 + s0 + mj) & M
    return [(p + q) & M for p, q in zip(h, (a, b, c, d, e, f, g, hh))]


def crc_table():
    t = []
    for n in range(256):
        c = n
        for _ in range(8):
            c = (0xEDB88320 ^ (c >> 1)) if c & 1 else c >> 1
        t.append(c)
    return t


def main():
    data = open(sys.argv[1], "rb").read()
    if len(sys.argv) > 2:
        data = data[:int(sys.argv[2])]
    t = crc_table()
    crc = M
    for b in data:
        crc = t[(crc ^ b) & 0xFF] ^ (crc >> 8)
    crc ^= M
    n = len(data)
    padded = data + b"\x80" + b"\0" * ((55 - n) % 64) + (n * 8).to_bytes(8, "big")
    h = H0
    for i in range(0, len(padded), 64):
        h = compress(h, padded[i:i + 64])
    print("%08x" % crc)
    print("".join("%08x" % x for x in h))


main()
