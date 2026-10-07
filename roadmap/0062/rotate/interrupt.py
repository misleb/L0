"""Interrupt the rotator at every step, and at every pair of steps, and check
that what it leaves is consistent and that running it again finishes the
rotation exactly as an uninterrupted run would.

Usage: python3 interrupt.py ROTATE_BINARY WORKDIR

"Consistent" means: every file holds what one of the original files held, or
nothing (the new log); no original's contents are in two files; and the only
original whose contents may be gone is the oldest, LOG.N, and only once
LOG.N-1 has been renamed over it.
"""
import itertools
import os
import shutil
import subprocess
import sys

BIN = sys.argv[1]
WORK = sys.argv[2]

def names(n, extra):
    return ["log"] + ["log.%d" % i for i in range(1, n + 1 + extra)]

def setup(d, present, n, extra):
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for i in present:
        with open(os.path.join(d, names(n, extra)[i]), "w") as f:
            f.write("contents %d\n" % i)

def state(d):
    out = {}
    for name in sorted(os.listdir(d)):
        if name.startswith("log"):
            out[name] = open(os.path.join(d, name)).read()
    return out

def expected(present, n, extra):
    """Simulate the rotation's renames, skipping a missing source."""
    files = {names(n, extra)[i]: "contents %d\n" % i for i in present}
    for s in range(n):
        src = "log" if s == n - 1 else "log.%d" % (n - 1 - s)
        dst = "log.%d" % (n - s)
        if src in files:
            files[dst] = files.pop(src)
    files.setdefault("log", "")
    for i in range(n + 1, n + 1 + extra):
        files.pop("log.%d" % i, None)    # older than n keeps: deleted
    return files                         # and no journal: deleted when done

def run(d, n, stop=None):
    cmd = [BIN, os.path.join(d, "log"), str(n)]
    if stop is not None:
        cmd += ["--stop-after", str(stop)]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.returncode, p.stderr.decode()

def consistent(st, present, n, extra):
    originals = {"contents %d\n" % i: i for i in present}
    seen = {}
    for name, text in st.items():
        if name.startswith("log.rotating"):
            continue                    # the journal, while a rotation is under way
        if text == "":
            if name != "log":
                return "an empty file other than the log: " + name
            continue
        if text not in originals:
            return "unknown contents in " + name
        if text in seen:
            return "contents %r in both %s and %s" % (text, seen[text], name)
        seen[text] = name
    for text, i in originals.items():
        if text not in seen and i < n:
            return "lost the contents of " + names(n, extra)[i]
    return None

def check_case(label, present, n, extra, failures):
    d = os.path.join(WORK, "case")
    setup(d, present, n, extra)
    status, err = run(d, n)
    want = expected(present, n, extra)
    if status != 0 or state(d) != want:
        failures.append("%s: plain run gave %s, status %d %s" % (label, state(d), status, err))
        return 0
    total = 0
    k = 0
    while True:
        setup(d, present, n, extra)
        status, err = run(d, n, k)
        if status == 0:
            break                       # k is past the last step: nothing interrupted
        total += 1
        if status != 3:
            failures.append("%s: stop at %d gave status %d %s" % (label, k, status, err))
        bad = consistent(state(d), present, n, extra)
        if bad:
            failures.append("%s: stopped after %d: %s" % (label, k, bad))
        status, err = run(d, n)
        if status != 0 or state(d) != want:
            failures.append("%s: resume after %d gave %s, want %s" % (label, k, state(d), want))
        k += 1
    # Interrupted twice: once, and then again while finishing.
    for k1, k2 in itertools.product(range(k), range(k)):
        setup(d, present, n, extra)
        run(d, n, k1)
        status, err = run(d, n, k2)
        bad = consistent(state(d), present, n, extra)
        if bad:
            failures.append("%s: stopped after %d then %d: %s" % (label, k1, k2, bad))
        if status == 3:
            run(d, n)                   # the second run was interrupted too: finish it
        if state(d) != want:
            failures.append("%s: resume after %d then %d gave %s" % (label, k1, k2, state(d)))
        total += 1
    return total

def kill_test(failures, runs):
    """Kill a rotation of 200 files with SIGKILL at a random moment, without
    the hook, then finish it and compare."""
    import random
    import time
    rng = random.Random(55)
    n = 200
    present = list(range(n + 1))
    d = os.path.join(WORK, "case")
    want = expected(present, n, 0)
    killed = 0
    for r in range(runs):
        setup(d, present, n, 0)
        p = subprocess.Popen([BIN, os.path.join(d, "log"), str(n)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(rng.uniform(0, 0.03))
        p.kill()
        status = p.wait()
        if status != 0:
            killed += 1
        bad = consistent(state(d), present, n, 0)
        if bad:
            failures.append("kill run %d: %s" % (r, bad))
        run(d, n)
        if state(d) != want:
            failures.append("kill run %d: finished as %s" % (r, sorted(state(d).items())[:4]))
    return killed

def main():
    failures = []
    total = 0
    killed = kill_test(failures, 200)
    print("%d of 200 runs killed part way" % killed)
    cases = [
        ("n=1 full", [0, 1], 1, 0),
        ("n=3 full", [0, 1, 2, 3], 3, 0),
        ("n=3 only log", [0], 3, 0),
        ("n=3 gap at 2", [0, 1, 3], 3, 0),
        ("n=3 no log", [1, 2], 3, 0),
        ("n=3 extra beyond", [0, 1, 2, 3, 4, 5], 3, 2),
        ("n=5 full", [0, 1, 2, 3, 4, 5], 5, 0),
    ]
    for label, present, n, extra in cases:
        total += check_case(label, present, n, extra, failures)
    for f in failures:
        print("FAIL", f)
    print("%d interrupted runs checked, %d failures" % (total, len(failures)))
    sys.exit(1 if failures else 0)

main()
