"""Check an L0 archive independently of the L0 code: the format, every Adler-32
against zlib's, and optionally that every entry matches a file on disk.

Usage: python3 verify.py ARCHIVE [ROOT]
  ROOT, if given, is where each entry's name is looked up to compare contents.
"""
import os
import sys
import zlib

def u64(b, i):
    return int.from_bytes(b[i:i + 8], "big")

def main():
    b = open(sys.argv[1], "rb").read()
    root = sys.argv[2] if len(sys.argv) > 2 else None
    assert b[:8] == b"L0ARCH1\n", "magic"
    count = u64(b, 8)
    assert zlib.adler32(b[8:16]) == u64(b, 16), "count sum"
    pos = 24
    for k in range(count):
        nl, dl, hs, ds = u64(b, pos), u64(b, pos + 8), u64(b, pos + 16), u64(b, pos + 24)
        assert zlib.adler32(b[pos:pos + 16]) == hs, "head sum %d" % k
        start = pos + 32
        name = b[start:start + nl]
        body = b[start + nl:start + nl + dl]
        assert zlib.adler32(name + body) == ds, "data sum %d" % k
        if root is not None:
            with open(os.path.join(root, name.decode()), "rb") as f:
                assert f.read() == body, "contents of %s" % name
        pos = start + nl + dl
    assert b[pos:] == b"L0ARCEND", "end marker"
    print("ok:", count, "entries,", len(b), "bytes")

main()
