#!/usr/bin/env python3
"""Writes pseudo-random English-like text to stdout, for timing wordfreq.

usage: gen.py MEGABYTES VOCABULARY [SEED]

Words are drawn from a Zipf-like distribution over VOCABULARY made-up words,
with mixed case, punctuation, and line breaks, so the input looks like prose.
"""
import random
import sys


def main():
    mb = float(sys.argv[1])
    vocab_size = int(sys.argv[2])
    rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    letters = "abcdefghijklmnopqrstuvwxyz"
    vocab = set()
    while len(vocab) < vocab_size:
        vocab.add("".join(rng.choice(letters) for _ in range(rng.randint(1, 12))))
    vocab = sorted(vocab)
    rng.shuffle(vocab)
    weights = [1.0 / (i + 1) for i in range(len(vocab))]
    target = int(mb * 1024 * 1024)
    out = []
    size = 0
    col = 0
    while size < target:
        words = rng.choices(vocab, weights, k=1000)
        for w in words:
            r = rng.random()
            if r < 0.1:
                w = w.capitalize()
            elif r < 0.12:
                w = w.upper()
            sep = rng.choice(" " * 12 + ",.;:!?-'\"()")
            piece = w + sep
            col += len(piece)
            if col > 72:
                piece += "\n"
                col = 0
            out.append(piece)
            size += len(piece)
    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()
