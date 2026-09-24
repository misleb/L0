#!/bin/sh
# timing.sh -- feed counter one line per second, as a person typing would,
# and timestamp when each line's report appears. An awk program with the same
# output, flushing after each line, is the reference.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tl="$here/../common/timeline.py"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/counter.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

"$root/tools/l0" build "$here/counter.l0" -o "$tmp/counter"

feed() {
    python3 "$tl" --at 0 'a b a\n' --at 1 'b\n' --at 2 'c a\n' --eof 3 -- "$@"
}

echo "counter:"
feed "$tmp/counter"
echo
echo "awk, flushing per line (reference):"
feed awk '{ s = ""
    for (i = 1; i <= NF; i++) { c[$i]++; s = s (i > 1 ? " " : "") $i "=" c[$i] }
    print s; fflush() }'
