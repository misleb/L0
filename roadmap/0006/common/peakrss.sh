#!/bin/sh
# peakrss.sh PROG INPUT OUTPUT -- run PROG < INPUT > OUTPUT under
# /usr/bin/time -l (macOS) and print "exit rss_bytes footprint_bytes seconds"
# on one line.
#
# rss is "maximum resident set size". Under memory pressure macOS compresses
# pages, and compressed pages are not resident, so rss undercounts what the
# process allocated; footprint ("peak memory footprint") counts them. On
# Linux, /usr/bin/time -v has only the resident size, in kilobytes, and
# footprint is reported as the same number.
set -u
prog=$1; input=$2; output=$3
err=$(mktemp "${TMPDIR:-/tmp}/peakrss.XXXXXX")
if [ "$(uname)" = Darwin ]; then
    /usr/bin/time -l "$prog" < "$input" > "$output" 2> "$err"
    code=$?
    rss=$(awk '/maximum resident set size/ {print $1}' "$err")
    foot=$(awk '/peak memory footprint/ {print $1}' "$err")
    secs=$(awk '/ real / {print $1}' "$err")
else
    /usr/bin/time -v "$prog" < "$input" > "$output" 2> "$err"
    code=$?
    rss=$(awk -F: '/Maximum resident set size/ {gsub(/ /,"",$2); print $2 * 1024}' "$err")
    foot=$rss
    secs=$(awk -F': ' '/Elapsed \(wall clock\)/ {print $2}' "$err")
fi
if grep -q 'l0: runtime error' "$err"; then
    grep 'l0: runtime error' "$err" >&2
fi
rm -f "$err"
echo "$code $rss $foot $secs"
