#!/bin/sh
# measure.sh LABEL OUTFILE CMD ARGS...   run CMD with stdout to OUTFILE and
# print one line: label, wall seconds, peak resident MB, and any L0 array stats.
label=$1; out=$2; shift 2
log=$(dirname "$out")/.measure.$$.log
L0_ARRAY_STATS=1 /usr/bin/time -l "$@" > "$out" 2> "$log"
status=$?
real=$(awk '/ real /{print $1}' "$log")
rss=$(awk '/maximum resident set size/{printf "%.1f", $1/1048576}' "$log")
copies=$(awk -F': ' '/array copies/{print $NF}' "$log")
inplace=$(awk -F': ' '/sets in place/{print $NF}' "$log")
words=$(awk -F': ' '/words copied/{print $NF}' "$log")
printf '%-28s status=%s real=%ss peak=%sMB copies=%s in_place=%s words_copied=%s\n' \
  "$label" "$status" "$real" "$rss" "${copies:--}" "${inplace:--}" "${words:--}"
grep -v -E 'array|real|resident|^ +[0-9]+ +[a-z]|time:' "$log" | head -5
rm -f "$log"
