"""Reference Sudoku solver and hard-puzzle file maker, for comparing with L0.

    python3 sudoku.py make N SEED > hard.txt   known hard puzzles, then N minimal
                                              puzzles generated from random grids
    python3 sudoku.py solve hard.txt           one line per puzzle, as the L0 program

solve is the L0 program's algorithm: the empty cell with the fewest
candidates (the first on a tie, stopping at one with 0 or 1), digits in
increasing order, flags per row, column, and box in flat lists, undone on
the way back.
"""
import random
import sys

KNOWN = [
    # Arto Inkala's 2012 "world's hardest"
    "8..........36......7..9.2...5...7.......457.....1...3...1....68..85...1..9....4..",
    # the first five of the top95 list
    "4.....8.5.3..........7......2.....6.....8.4......1.......6.3.7.5..2.....1.4......",
    "52...6.........7.13...........4..8..6......5...........418.........3..2...87.....",
    "6.....8.3.4.7.................5.4.7.3..2.....1.6.......2.....5.....8.6......1....",
    "48.3............71.2.......7.5....6....2..8.............1.76...3.....4......5....",
    "....14....3....2...7..........9...3.6.1.............8.2.....1.4....5.6.....7.8...",
    # "Golden Nugget" and "Easter Monster"
    ".......39.....1..5..3.5.8....8.9...6.7...2..1..4.......9.8..5..2....6..4..7.....",
    "1.......2.9.4...5...6...7...5.9.3.......7.......85..4.7.....6...3...9.8...2.....1",
]


def box(i):
    return (i // 27) * 3 + (i % 9) // 3


class Solver:
    def __init__(self, cells):
        self.b = [0] * 81
        self.rf, self.cf, self.xf = [0] * 90, [0] * 90, [0] * 90
        self.nodes = 0
        self.ok = True
        for i, d in enumerate(cells):
            if d:
                if not self.free(i, d):
                    self.ok = False
                    return
                self.put(i, d, 1)

    def free(self, i, d):
        return not (self.rf[i // 9 * 10 + d] or self.cf[i % 9 * 10 + d] or self.xf[box(i) * 10 + d])

    def put(self, i, d, on):
        self.b[i] = d * on
        self.rf[i // 9 * 10 + d] = on
        self.cf[i % 9 * 10 + d] = on
        self.xf[box(i) * 10 + d] = on

    def pick(self):
        best, least = -1, 10
        for i in range(81):
            if self.b[i]:
                continue
            n = sum(1 for d in range(1, 10) if self.free(i, d))
            if n <= 1:
                return i
            if n < least:
                best, least = i, n
        return best

    def solve(self):
        i = self.pick()
        if i < 0:
            return True
        for d in range(1, 10):
            if self.free(i, d):
                self.nodes += 1
                self.put(i, d, 1)
                if self.solve():
                    return True
                self.put(i, d, 0)
        return False


def parse(line):
    line = line.strip()
    return [0 if c in ".0" else int(c) for c in line]


def count_solutions(cells, limit=2):
    s = Solver(cells)
    if not s.ok:
        return 0
    found = [0]

    def go():
        i = s.pick()
        if i < 0:
            found[0] += 1
            return found[0] >= limit
        for d in range(1, 10):
            if s.free(i, d):
                s.put(i, d, 1)
                if go():
                    return True
                s.put(i, d, 0)
        return False
    go()
    return found[0]


def random_grid(rnd):
    s = Solver([0] * 81)

    def go():
        i = s.pick()
        if i < 0:
            return True
        ds = list(range(1, 10))
        rnd.shuffle(ds)
        for d in ds:
            if s.free(i, d):
                s.put(i, d, 1)
                if go():
                    return True
                s.put(i, d, 0)
        return False
    go()
    return s.b[:]


def minimal_puzzle(rnd):
    cells = random_grid(rnd)
    order = list(range(81))
    rnd.shuffle(order)
    for i in order:
        keep = cells[i]
        cells[i] = 0
        if count_solutions(cells) != 1:
            cells[i] = keep
    return "".join(str(d) if d else "." for d in cells)


def make(n, seed):
    rnd = random.Random(seed)
    for p in KNOWN:
        if count_solutions(parse(p)) != 1:
            sys.stderr.write("not unique, skipped: %s\n" % p)
            continue
        print(p)
    for _ in range(n):
        print(minimal_puzzle(rnd))


def solve_file(path):
    nodes = 0
    for line in open(path):
        if not line.strip():
            continue
        s = Solver(parse(line))
        if s.ok and s.solve():
            print("".join(map(str, s.b)))
        else:
            print("no solution")
        nodes += s.nodes
    sys.stderr.write("nodes: %d\n" % nodes)


if __name__ == "__main__":
    if sys.argv[1] == "make":
        make(int(sys.argv[2]), int(sys.argv[3]))
    else:
        solve_file(sys.argv[2])
