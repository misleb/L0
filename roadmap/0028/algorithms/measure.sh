#!/bin/sh
# measure.sh LABEL CMD... -- runs CMD under /usr/bin/time -l, prints
# "LABEL: R s, M MB peak" and keeps stdout in LABEL.out and stderr in LABEL.err
# under results/.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/results"
label=$1; shift
/usr/bin/time -l "$@" > "$here/results/$label.out" 2> "$here/results/$label.err" || {
    echo "$label: exited $?"; tail -5 "$here/results/$label.err"; exit 1; }
real=$(awk '/ real /{print $1}' "$here/results/$label.err")
rss=$(awk '/maximum resident set size/{printf "%.1f", $1/1048576}' "$here/results/$label.err")
echo "$label: ${real} s, ${rss} MB peak"
