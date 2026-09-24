#!/bin/sh
# measure.sh [MB ...] -- build counter, run it on generated inputs of the given
# sizes (default 1 10 100) whose vocabulary is 14 words, check its output
# against an awk reference, and print a markdown table of peak memory. Inputs
# are generated into a temporary directory and deleted afterward.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/counter.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

"$root/tools/l0" build "$here/counter.l0" -o "$tmp/counter"

[ $# -gt 0 ] || set -- 1 10 100
echo "| input | input bytes | lines | output bytes | max RSS | peak footprint | footprint / input byte | time (s) | matches awk |"
echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
for mb in "$@"; do
    "$here/../common/genlines.sh" "$mb" noid > "$tmp/in"
    read code rss foot secs <<EOF
$("$here/../common/peakrss.sh" "$tmp/counter" "$tmp/in" "$tmp/out")
EOF
    awk '{ s = ""
           for (i = 1; i <= NF; i++) { c[$i]++; s = s (i > 1 ? " " : "") $i "=" c[$i] }
           print s }' "$tmp/in" > "$tmp/want"
    if cmp -s "$tmp/out" "$tmp/want"; then same=yes; else same="no (exit $code)"; fi
    inb=$(wc -c < "$tmp/in" | tr -d ' ')
    lines=$(wc -l < "$tmp/in" | tr -d ' ')
    outb=$(wc -c < "$tmp/out" | tr -d ' ')
    awk -v mb="$mb" -v i="$inb" -v n="$lines" -v o="$outb" -v r="$rss" \
        -v f="$foot" -v s="$secs" -v ok="$same" 'BEGIN {
        printf "| %s MB | %d | %d | %d | %.1f MB | %.1f MB | %.1f | %s | %s |\n",
               mb, i, n, o, r / 1048576, f / 1048576, f / i, s, ok }'
    rm -f "$tmp/in" "$tmp/out" "$tmp/want"
done
