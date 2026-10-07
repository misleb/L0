"""Expected CRC-32 and SHA-256 values for the L0 tests in ../hash/sums_test.l0."""
import hashlib
import zlib

cases = [
    ("empty", b""),
    ("abc", b"abc"),
    ("fox", b"The quick brown fox jumps over the lazy dog"),
    ("nist2", b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
]
for n in (55, 56, 63, 64, 65, 119, 120, 128, 1000):
    cases.append(("a%d" % n, b"a" * n))
# every byte value, twice, so the table entries are all exercised
cases.append(("allbytes", bytes(range(256)) * 2))

for name, data in cases:
    print(name, len(data), "%08x" % zlib.crc32(data), zlib.crc32(data),
          hashlib.sha256(data).hexdigest())
