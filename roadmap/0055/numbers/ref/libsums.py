"""CRC-32 and SHA-256 of a file with Python's zlib and hashlib (both in C),
reading 1 MB at a time. Usage: libsums.py FILE"""
import hashlib
import sys
import zlib

crc, sha = 0, hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            break
        crc = zlib.crc32(chunk, crc)
        sha.update(chunk)
print("%08x" % crc)
print(sha.hexdigest())
