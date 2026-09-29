#!/usr/bin/env python3
"""Writes MEGABYTES of lines to stdout, for timing sort.

usage: gen_lines.py MEGABYTES [SEED]

Lines are 0 to 120 bytes of words from a small vocabulary, so many share long
prefixes and some repeat exactly. About one line in fifty holds bytes 128 and
above, one in a hundred a tab or carriage return, and one in two hundred is
empty, so a bytewise order is really tested. The last line has no newline.
"""
import random
import sys


def main():
    mb = float(sys.argv[1])
    rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    vocab = ["".join(rng.choice(letters) for _ in range(rng.randint(1, 10)))
             for _ in range(3000)]
    target = int(mb * 1024 * 1024)
    out = []
    size = 0
    while size < target:
        r = rng.random()
        if r < 0.005:
            line = b""
        else:
            words = []
            n = 0
            want = rng.randint(1, 120)
            while n < want:
                w = rng.choice(vocab[: rng.choice([30, 300, 3000])])
                words.append(w)
                n += len(w) + 1
            line = " ".join(words)[:want].encode()
            if r < 0.025:
                line = line + bytes([rng.randint(128, 255)]) + b"x"
            elif r < 0.035:
                line = rng.choice([b"\t", b"\r", b"~"]) + line
        out.append(line + b"\n")
        size += len(line) + 1
    data = b"".join(out)
    sys.stdout.buffer.write(data[:-1])


if __name__ == "__main__":
    main()
