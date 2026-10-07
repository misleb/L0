"""Copy a file, adding 1 to the byte at OFFSET.

Usage: python3 corrupt.py IN OUT OFFSET
"""
import sys

b = bytearray(open(sys.argv[1], "rb").read())
i = int(sys.argv[3])
b[i] = (b[i] + 1) % 256
open(sys.argv[2], "wb").write(bytes(b))
