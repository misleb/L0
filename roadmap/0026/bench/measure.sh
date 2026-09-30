#!/bin/sh
# measure.sh LABEL PROGRAM INPUT [EXPECTED|-] [ARGS...]
#
# Runs PROGRAM on INPUT once to warm up, then three times under
# /usr/bin/time -l, and prints the median wall time, user time, and peak
# resident memory, with peak bytes per input byte. When EXPECTED is a file,
# the output of the last run must equal it byte for byte, or the line says
# DIFFERS. /usr/bin/time -l reports memory only outside the sandbox.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
label=$1
prog=$2
input=$3
expected=${4:--}
shift 3
[ $# -gt 0 ] && shift
work=$(mktemp -d "$root/tmp/measure.XXXXXX")
"$prog" "$@" < "$input" > /dev/null 2>&1 || true
for i in 1 2 3; do
    /usr/bin/time -l "$prog" "$@" < "$input" > "$work/out" 2> "$work/t$i" || true
done
summary=$(for i in 1 2 3; do
    awk '/ real /{r=$1; u=$3} /maximum resident/{m=$1} END{printf "%s %s %s\n", r, u, m}' "$work/t$i"
done | sort -n | sed -n 2p)
size=$(wc -c < "$input" | tr -d ' ')
check=""
if [ "$expected" != "-" ]; then
    if cmp -s "$work/out" "$expected"; then check="identical"; else check="DIFFERS"; fi
fi
echo "$summary" | awk -v l="$label" -v s="$size" -v c="$check" \
    '{printf "%-34s %6.2f s real %6.2f s user %8.1f MB %6.1f B/B %s\n", l, $1, $2, $3/1048576, $3/s, c}'
rm -rf "$work"
