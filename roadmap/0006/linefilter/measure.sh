#!/bin/sh
# measure.sh [MB ...] -- build linefilter, run it on generated inputs of the
# given sizes (default 1 10 100), check its output against grep, and print a
# markdown table of peak memory. Inputs are generated into a temporary
# directory and deleted afterward.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/linefilter.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

"$root/tools/l0" build "$here/linefilter.l0" -o "$tmp/linefilter"

[ $# -gt 0 ] || set -- 1 10 100
echo "| input | input bytes | output bytes | max RSS | peak footprint | footprint / input byte | time (s) | matches grep |"
echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
for mb in "$@"; do
    "$here/../common/genlines.sh" "$mb" > "$tmp/in"
    read code rss foot secs <<EOF
$("$here/../common/peakrss.sh" "$tmp/linefilter" "$tmp/in" "$tmp/out")
EOF
    grep ERROR "$tmp/in" > "$tmp/want" || true
    if cmp -s "$tmp/out" "$tmp/want"; then same=yes; else same="no (exit $code)"; fi
    inb=$(wc -c < "$tmp/in" | tr -d ' ')
    outb=$(wc -c < "$tmp/out" | tr -d ' ')
    awk -v mb="$mb" -v i="$inb" -v o="$outb" -v r="$rss" -v f="$foot" \
        -v s="$secs" -v ok="$same" 'BEGIN {
        printf "| %s MB | %d | %d | %.1f MB | %.1f MB | %.1f | %s | %s |\n",
               mb, i, o, r / 1048576, f / 1048576, f / i, s, ok }'
    rm -f "$tmp/in" "$tmp/out" "$tmp/want"
done
