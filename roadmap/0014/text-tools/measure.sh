#!/bin/sh
# measure.sh PROGRAM INPUT [ARGS...] -- runs PROGRAM twice on INPUT, discarding
# output, and prints wall time, CPU time, and peak resident memory of the
# second run. The first run absorbs macOS's one-time check of a new binary,
# which otherwise adds about a second to whatever was just linked.
set -eu
prog=$1
input=$2
shift 2
t=$(mktemp)
"$prog" "$@" < "$input" > /dev/null 2>&1 || true
/usr/bin/time -l "$prog" "$@" < "$input" > /dev/null 2> "$t" || true
real=$(awk '/ real /{print $1}' "$t")
user=$(awk '/ real /{print $3}' "$t")
rss=$(awk '/maximum resident/{printf "%.1f", $1 / 1048576}' "$t")
echo "$(basename "$prog") < $(basename "$input"): ${real}s real, ${user}s user, ${rss} MB peak RSS"
rm -f "$t"
