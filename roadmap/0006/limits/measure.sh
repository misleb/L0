#!/bin/sh
# measure.sh -- build the three memory limits (01, 02, 03) and print a
# markdown table of peak memory for each, across input sizes. Inputs are
# generated into a temporary directory and deleted afterward.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
common="$here/../common"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/limits.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

for p in 01-input-read-whole 02-no-reclamation 03-output-held-until-exit; do
    "$root/tools/l0" build "$here/$p.l0" -o "$tmp/$p"
done

# row LABEL QUANTITY PROG: runs PROG on $tmp/in; QUANTITY is what the
# per-unit column divides by (input bytes, cells allocated, output bytes).
row() {
    read code rss foot secs <<EOF
$("$common/peakrss.sh" "$tmp/$3" "$tmp/in" "$tmp/out")
EOF
    outb=$(wc -c < "$tmp/out" | tr -d ' ')
    awk -v l="$1" -v q="$2" -v r="$rss" -v f="$foot" -v s="$secs" \
        -v c="$code" -v o="$outb" 'BEGIN {
        printf "| %s | %.1f MB | %.1f MB | %.1f | %s | %d | %s |\n",
               l, r / 1048576, f / 1048576, f / q, s, c, o }'
}

echo "### 01-input-read-whole: main returns 0 without reading its input"
echo
echo "| input | max RSS | peak footprint | footprint / input byte | time (s) | exit | output bytes |"
echo "| --- | --- | --- | --- | --- | --- | --- |"
for mb in 1 10 100; do
    "$common/genlines.sh" "$mb" > "$tmp/in"
    row "$mb MB" "$(wc -c < "$tmp/in" | tr -d ' ')" 01-input-read-whole
done
echo

echo "### 02-no-reclamation: N iterations, each builds and drops a 64-cell list"
echo
echo "| N | max RSS | peak footprint | footprint / cell made | time (s) | exit | output bytes |"
echo "| --- | --- | --- | --- | --- | --- | --- |"
for n in 1000 100000 1000000 10000000; do
    echo "$n" > "$tmp/in"
    row "$n" "$((n * 64))" 02-no-reclamation
done
echo

echo "### 03-output-held-until-exit: N lines of \"y\\\\n\" from a one-line input"
echo
echo "| output | max RSS | peak footprint | footprint / output byte | time (s) | exit | output bytes |"
echo "| --- | --- | --- | --- | --- | --- | --- |"
for mb in 1 10 100; do
    echo "$((mb * 524288))" > "$tmp/in"
    row "$mb MB" "$((mb * 1048576))" 03-output-held-until-exit
done
