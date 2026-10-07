"""A buffer and a script of edits for editor, under the directory given.

  gen_edits.py OUT [LINES] [EDITS]

OUT/buffer.txt has LINES lines (100,000); OUT/script.txt has EDITS commands
(100,000): inserts, replaces, deletes, undos (sometimes several in a row),
redos, and line prints, every one valid, then one print of the whole
buffer. Validity is kept by tracking the buffer's length through undo and
redo as the editor would.
"""
import os
import random
import sys

out = sys.argv[1]
lines = int(sys.argv[2]) if len(sys.argv) > 2 else 100_000
edits = int(sys.argv[3]) if len(sys.argv) > 3 else 100_000
os.makedirs(out, exist_ok=True)
rng = random.Random(55)
words = "alpha beta gamma delta epsilon zeta eta theta iota kappa".split()


def text():
    return " ".join(rng.choice(words) for _ in range(rng.randint(1, 8)))


with open(os.path.join(out, "buffer.txt"), "w") as f:
    for i in range(lines):
        f.write(f"line {i} {text()}\n")

size, undo, redo = lines, [], []
cmds = []


def edit(new):
    global size, redo
    undo.append(size)
    redo = []
    size = new


while len(cmds) < edits:
    r = rng.random()
    if r < 0.30:
        n = rng.randint(0, size)
        cmds.append(f"i {n} {text()}")
        edit(size + 1)
    elif r < 0.60 and size > 0:
        cmds.append(f"r {rng.randrange(size)} {text()}")
        edit(size)
    elif r < 0.80 and size > 0:
        cmds.append(f"d {rng.randrange(size)}")
        edit(size - 1)
    elif r < 0.92 and undo:
        for _ in range(rng.choice([1, 1, 1, 2, 5])):
            if undo and len(cmds) < edits:
                cmds.append("u")
                redo.append(size)
                size = undo.pop()
    elif r < 0.97 and redo:
        cmds.append("R")
        undo.append(size)
        size = redo.pop()
    elif size > 0:
        cmds.append(f"l {rng.randrange(size)}")

with open(os.path.join(out, "script.txt"), "w") as f:
    f.write("\n".join(cmds) + "\np\n")
