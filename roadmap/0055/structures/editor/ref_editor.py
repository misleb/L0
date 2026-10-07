"""The reference for editor: the same script language, in Python.

  ref_editor.py FILE < SCRIPT

The buffer is a list of lines. Python has no persistent sequence, and
copying the list per edit to keep old versions would be quadratic, so undo
is what a Python editor would do instead: each edit records its inverse.
"""
import sys


def main(path):
    with open(path, "rb") as f:
        buf = f.read().split(b"\n")
    if buf and buf[-1] == b"":
        buf.pop()
    out = sys.stdout.buffer
    undo, redo = [], []
    status = 0

    def do(op):
        """Apply op and return its inverse."""
        kind, n, *rest = op
        if kind == "i":
            buf.insert(n, rest[0])
            return ("d", n)
        if kind == "d":
            old = buf.pop(n)
            return ("i", n, old)
        old = buf[n]
        buf[n] = rest[0]
        return ("r", n, old)

    for raw in sys.stdin.buffer:
        line = raw.rstrip(b"\n")
        c = line[:1]
        why = None
        if c in (b"i", b"d", b"r", b"l"):
            parts = line[1:].lstrip(b" ")
            digits = len(parts) - len(parts.lstrip(b"0123456789"))
            if digits == 0:
                why = "expected a line number"
            else:
                n = int(parts[:digits])
                txt = parts[digits:]
                if txt[:1] == b" ":
                    txt = txt[1:]
                limit = len(buf) + (1 if c == b"i" else 0)
                if n >= limit:
                    why = "no such line"
                elif c == b"l":
                    out.write(buf[n] + b"\n")
                else:
                    op = ("i", n, txt) if c == b"i" else ("d", n) if c == b"d" else ("r", n, txt)
                    undo.append(do(op))
                    redo.clear()
        elif line == b"u":
            if undo:
                redo.append(do(undo.pop()))
            else:
                why = "nothing to undo"
        elif line == b"R":
            if redo:
                undo.append(do(redo.pop()))
            else:
                why = "nothing to redo"
        elif line == b"p":
            out.writelines(b + b"\n" for b in buf)
        else:
            why = "unknown command"
        if why:
            sys.stderr.write(f"?{line.decode()}: {why}\n")
            status = 1
    return status


sys.exit(main(sys.argv[1]))
