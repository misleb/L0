#!/bin/sh
# measure.sh PROGRAM INPUT [ARGS...] -- runs PROGRAM twice on INPUT, discarding
# output, and prints wall time, user time, and peak resident memory of the
# second run. The first run absorbs macOS's one-time check of a new binary.
# 0014's measure.sh, with its temporary file kept in this directory.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
prog=$1
input=$2
shift 2
t=$(mktemp "$here/measure.XXXXXX")
"$prog" "$@" < "$input" > /dev/null 2>&1 || true
/usr/bin/time -l "$prog" "$@" < "$input" > /dev/null 2> "$t" || true
real=$(awk '/ real /{print $1}' "$t")
user=$(awk '/ real /{print $3}' "$t")
rss=$(awk '/maximum resident/{printf "%.1f", $1 / 1048576}' "$t")
echo "$(basename "$prog") $* < $(basename "$input"): ${real}s real, ${user}s user, ${rss} MB peak RSS"
rm -f "$t"
