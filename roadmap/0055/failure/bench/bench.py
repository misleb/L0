"""Run a command several times under /usr/bin/time -l and report the median
wall time and the largest peak resident set size.

Usage: python3 bench.py RUNS LABEL -- COMMAND...
       an optional --stdin FILE before -- feeds FILE to standard input,
       and --stdout FILE writes standard output there instead of discarding it.
"""
import re
import statistics
import subprocess
import sys

def main():
    argv = sys.argv[1:]
    runs = int(argv[0])
    label = argv[1]
    rest = argv[2:]
    stdin_path = None
    stdout_path = None
    while rest and rest[0] != "--":
        if rest[0] == "--stdin":
            stdin_path = rest[1]
        elif rest[0] == "--stdout":
            stdout_path = rest[1]
        rest = rest[2:]
    cmd = rest[1:]
    times = []
    rss = []
    for _ in range(runs):
        fin = open(stdin_path, "rb") if stdin_path else subprocess.DEVNULL
        fout = open(stdout_path, "wb") if stdout_path else subprocess.DEVNULL
        p = subprocess.run(["/usr/bin/time", "-l"] + cmd, stdin=fin, stdout=fout,
                           stderr=subprocess.PIPE)
        err = p.stderr.decode(errors="replace")
        m = re.search(r"([\d.]+) real", err)
        r = re.search(r"(\d+)\s+maximum resident set size", err)
        if p.returncode != 0 or not m:
            print(label, "failed with status", p.returncode)
            print(err)
            return
        times.append(float(m.group(1)))
        rss.append(int(r.group(1)))
    print("%-28s median %.2f s  (runs %s)  peak RSS %.1f MB" % (
        label, statistics.median(times), " ".join("%.2f" % t for t in times),
        max(rss) / 1e6))

main()
