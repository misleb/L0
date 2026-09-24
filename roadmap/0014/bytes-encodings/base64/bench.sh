#!/bin/sh
# Builds base64, checks a byte-exact round trip on random binary input, and
# times it against the system base64. Run from anywhere:
#
#   programs/base64/bench.sh [MEGABYTES]
#
# Each time is the best of three runs: the first run of a freshly linked
# binary on macOS includes a one-off check of the binary and is several
# times slower. Generated inputs go in a temporary directory and are deleted.

set -eu

MB=${1:-10}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=$(mktemp -d "${TMPDIR:-/tmp}/l0b64.XXXXXX")
trap 'rm -rf "$DIR"' EXIT

"$ROOT/tools/l0" build "$ROOT/programs/base64/base64.l0" \
    "$ROOT/programs/base64/base64_main.l0" -o "$DIR/base64"

head -c $((MB * 1048576)) /dev/urandom > "$DIR/in"

# best_of IN OUT CMD...: runs CMD < IN > OUT three times, prints the best
# wall time and the peak resident set in KB.
best_of() {
    in=$1; out=$2; shift 2
    best=""
    for i in 1 2 3; do
        /usr/bin/time -l "$@" < "$in" > "$out" 2> "$DIR/time"
        r=$(awk '/ real / {print $1}' "$DIR/time")
        m=$(awk '/maximum resident/ {print int($1 / 1024)}' "$DIR/time")
        if [ -z "$best" ] || [ "$(echo "$r < $best" | bc)" = 1 ]; then best=$r; fi
    done
    echo "${best}s, ${m} KB peak"
}

enc=$(best_of "$DIR/in" "$DIR/enc" "$DIR/base64")
dec=$(best_of "$DIR/enc" "$DIR/dec" "$DIR/base64" -d)
sysenc=$(best_of "$DIR/in" "$DIR/sysenc" base64)
sysdec=$(best_of "$DIR/sysenc" "$DIR/sysdec" base64 -d)

cmp "$DIR/in" "$DIR/dec" && echo "round trip: byte-exact on $MB MB"
if [ "$(tr -d '\n' < "$DIR/enc")" = "$(tr -d '\n' < "$DIR/sysenc")" ]; then
    echo "encoding: matches system base64, ignoring line breaks"
else
    echo "encoding: DIFFERS from system base64"
fi
base64 -d < "$DIR/enc" | cmp - "$DIR/in" && echo "system base64 decodes our output"
echo "l0 encode:     $enc"
echo "l0 decode:     $dec"
echo "system encode: $sysenc"
echo "system decode: $sysdec"
