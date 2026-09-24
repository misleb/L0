#!/usr/bin/env python3
"""What calc should print for each line of stdin, for comparing outputs on
large inputs. Division and remainder truncate toward zero, as in L0; errors
are reported only as "error", since only calc's wording is its own."""
import ast
import sys

LIMIT = 2**63


def ev(n):
    if isinstance(n, ast.Expression):
        return ev(n.body)
    if isinstance(n, ast.Constant):
        return n.value
    if isinstance(n, ast.UnaryOp):
        v = ev(n.operand)
        return -v if isinstance(n.op, ast.USub) else v
    a, b = ev(n.left), ev(n.right)
    if isinstance(n.op, ast.Add):
        r = a + b
    elif isinstance(n.op, ast.Sub):
        r = a - b
    elif isinstance(n.op, ast.Mult):
        r = a * b
    else:
        if b == 0:
            raise ZeroDivisionError
        q = abs(a) // abs(b) * (1 if (a >= 0) == (b >= 0) else -1)
        r = q if isinstance(n.op, ast.Div) else a - q * b
    if not -LIMIT <= r < LIMIT:
        raise OverflowError
    return r


out = sys.stdout
out.write("> ")
for line in sys.stdin:
    try:
        out.write(str(ev(ast.parse(line.strip(), mode="eval"))) + "\n")
    except Exception:
        out.write("error\n")
    out.write("> ")
out.write("\n")
