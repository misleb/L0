#!/usr/bin/env python3
"""measure.py RUNS PROGRAM [ARGS...] < input

Runs PROGRAM once to warm up (macOS checks a new binary once), then RUNS
times under /usr/bin/time -l, with stdin from the file given by --in, and
prints the mean and min wall time and the mean peak RSS. Output is
discarded; --out FILE keeps the last run's stdout.
"""
import os
import re
import subprocess
import sys
import tempfile


def one(argv, stdin_path, out_path, env):
    with tempfile.NamedTemporaryFile(mode="r", delete=False) as t:
        tpath = t.name
    stdin = open(stdin_path, "rb") if stdin_path else subprocess.DEVNULL
    stdout = open(out_path, "wb") if out_path else subprocess.DEVNULL
    subprocess.run(["/usr/bin/time", "-l", "-o", tpath] + argv,
                   stdin=stdin, stdout=stdout, stderr=subprocess.DEVNULL,
                   env=env)
    text = open(tpath).read()
    os.unlink(tpath)
    real = float(re.search(r"([\d.]+) real", text).group(1))
    rss = int(re.search(r"(\d+)\s+maximum resident set size", text).group(1))
    return real, rss


def main():
    args = sys.argv[1:]
    stdin_path = None
    out_path = None
    label = None
    env = dict(os.environ)
    while args and args[0].startswith("--"):
        if args[0] == "--in":
            stdin_path = args[1]
            args = args[2:]
        elif args[0] == "--out":
            out_path = args[1]
            args = args[2:]
        elif args[0] == "--label":
            label = args[1]
            args = args[2:]
        elif args[0] == "--env":
            k, v = args[1].split("=", 1)
            env[k] = v
            args = args[2:]
        else:
            break
    runs = int(args[0])
    argv = args[1:]
    one(argv, stdin_path, None, env)
    times = []
    rsss = []
    for i in range(runs):
        r, m = one(argv, stdin_path, out_path if i == runs - 1 else None, env)
        times.append(r)
        rsss.append(m)
    mean = sum(times) / len(times)
    print("%-28s mean %.3f s  min %.3f s  peak RSS %.1f MB  (%d runs)" % (
        label or os.path.basename(argv[0]), mean, min(times),
        sum(rsss) / len(rsss) / 1048576, runs))


main()
