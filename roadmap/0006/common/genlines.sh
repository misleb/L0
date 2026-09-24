#!/bin/sh
# genlines.sh MB [noid] -- write about MB megabytes of log-like text lines to
# stdout.
#
# Deterministic, so every run of a measurement sees the same bytes. Lines are
# about 45 bytes; one line in ten contains "ERROR". Each line starts with a
# sequence number unless "noid" is given; without it, every word comes from a
# vocabulary of 14, so a word counter's table stays small however large the
# input.
set -eu
mb=${1:?usage: genlines.sh MB [noid]}
noid=0
[ "${2:-}" = noid ] && noid=1
awk -v target=$((mb * 1048576)) -v noid=$noid 'BEGIN {
    split("alpha beta gamma delta epsilon zeta eta theta iota kappa", w, " ")
    n = 0; i = 0
    while (n < target) {
        lvl = (i % 10 == 7) ? "ERROR" : "INFO"
        line = sprintf("%s %s %s %s request served", lvl,
                       w[(i % 10) + 1], w[(i * 7 % 10) + 1], w[(i * 3 % 10) + 1])
        if (!noid) line = sprintf("%07d %s", i, line)
        print line
        n += length(line) + 1
        i++
    }
}'
