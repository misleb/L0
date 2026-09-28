#!/bin/sh
# array_histogram.sh EXE -- the byte histogram matches od's count, and every
# update of the counts happened in place: L0_ARRAY_STATS reports no copies.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/array_histogram.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }

awk 'BEGIN { s = 7; for (i = 0; i < 20000; i++) {
        line = ""; n = 1 + s % 40
        for (j = 0; j < n; j++) { s = (s * 1103515245 + 12345) % 2147483648
                                  line = line sprintf("%c", 32 + s % 95) }
        print line } }' > "$d/in"
od -An -v -tu1 "$d/in" | tr -s ' ' '\n' | sed '/^$/d' | sort -n | uniq -c |
    awk '{ print $2 " " $1 }' > "$d/want"

L0_ARRAY_STATS=1 "$exe" < "$d/in" > "$d/out" 2> "$d/err" ||
    fail "exited $?: $(cat "$d/err")"
cmp -s "$d/out" "$d/want" || fail "the histogram differs from od's"
grep -qx 'l0: array copies: 0' "$d/err" ||
    fail "an update copied: $(cat "$d/err")"
