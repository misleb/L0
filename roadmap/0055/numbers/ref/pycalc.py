"""The rational calculator of ../calc in Python, with Fraction (big integers),
printing exactly what the L0 program prints for every line it can answer.
Usage: pycalc.py [--int64] < expressions
  --int64   report an overflow, as the L0 program must, whenever a reduced
            result's numerator or denominator, or a literal, is outside
            -(2^63 - 1) .. 2^63 - 1"""
import sys
from fractions import Fraction

PLACES = 20
LIMIT = 2**63 - 1
INT64 = "--int64" in sys.argv


class CalcError(Exception):
    pass


def check(v):
    if INT64 and (abs(v.numerator) > LIMIT or v.denominator > LIMIT):
        raise CalcError("overflow: a number does not fit in 64 bits")
    return v


def q(c):
    return "'" + c + "'"


class Parser:
    def __init__(self, s):
        self.s, self.i = s, 0

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t":
            self.i += 1

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < len(self.s) else ""

    def expr(self):
        v = self.term()
        while self.peek() in ("+", "-"):
            op = self.s[self.i]
            self.i += 1
            w = self.term()
            v = check(v + w if op == "+" else v - w)
        return v

    def term(self):
        v = self.factor()
        while self.peek() in ("*", "/"):
            op = self.s[self.i]
            self.i += 1
            w = self.factor()
            if op == "/" and w == 0:
                raise CalcError("division by zero")
            v = check(v * w if op == "*" else v / w)
        return v

    def factor(self):
        c = self.peek()
        if c == "":
            raise CalcError("syntax: expected a number, -, or ( at the end")
        if c == "-":
            self.i += 1
            return -self.factor()
        if c == "(":
            self.i += 1
            v = self.expr()
            c = self.peek()
            if c != ")":
                raise CalcError("syntax: expected ) at the end" if c == ""
                                else "syntax: expected ) at " + q(c))
            self.i += 1
            return v
        if c.isdigit():
            j = self.i
            while self.i < len(self.s) and self.s[self.i].isdigit():
                self.i += 1
            return check(Fraction(int(self.s[j:self.i])))
        raise CalcError("syntax: expected a number, -, or ( at " + q(c))


def show(v):
    return str(v.numerator) if v.denominator == 1 else "%d/%d" % (v.numerator, v.denominator)


def decimal(v):
    m, d = abs(v.numerator), v.denominator
    r = (2 * m * 10**PLACES + d) // (2 * d)   # half away from zero
    ip, fr = divmod(r, 10**PLACES)
    return "%s%d.%0*d" % ("-" if v < 0 else "", ip, PLACES, fr)


def line(s):
    p = Parser(s)
    try:
        v = p.expr()
        c = p.peek()
        if c != "":
            raise CalcError("syntax: unexpected " + q(c))
        return show(v) + " = " + decimal(v)
    except CalcError as e:
        return "error: " + str(e)


def main():
    out = []
    for raw in sys.stdin.buffer.read().split(b"\n"):
        s = raw.decode("latin-1").rstrip("\r")
        if s.strip(" \t") == "":
            continue
        out.append(line(s))
    sys.stdout.write("".join(x + "\n" for x in out))


main()
