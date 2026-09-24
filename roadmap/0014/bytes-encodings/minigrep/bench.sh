#!/bin/sh
# Times minigrep against the system grep on a generated text file of about
# MEGABYTES MB, for a few patterns. Run from anywhere:
#
#   programs/minigrep/bench.sh [MEGABYTES]          default 20
#
# Each time is the best of three runs. Inputs are deleted afterward.

set -eu

MB=${1:-20}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=$(mktemp -d "${TMPDIR:-/tmp}/l0grep.XXXXXX")
trap 'rm -rf "$DIR"' EXIT

"$ROOT/tools/l0" build "$ROOT/programs/minigrep/minigrep.l0" \
    "$ROOT/programs/minigrep/minigrep_main.l0" -o "$DIR/minigrep"

# Lines of three to twelve words from a small vocabulary, about 50 bytes each.
awk -v bytes=$((MB * 1048576)) 'BEGIN {
    srand(1)
    split("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu", w, " ")
    total = 0
    while (total < bytes) {
        k = 3 + int(rand() * 10); s = ""
        for (j = 0; j < k; j++) s = s (j ? " " : "") w[1 + int(rand() * 12)]
        print s; total += length(s) + 1
    }
}' > "$DIR/text"

best_of() {
    best=""
    for i in 1 2 3; do
        set +e
        /usr/bin/time -l "$@" > "$DIR/out" 2> "$DIR/time"
        set -e
        r=$(awk '/ real / {print $1}' "$DIR/time")
        m=$(awk '/maximum resident/ {print int($1 / 1024)}' "$DIR/time")
        if [ -z "$best" ] || [ "$(echo "$r < $best" | bc)" = 1 ]; then best=$r; fi
    done
    echo "${best}s ${m}KB $(wc -l < "$DIR/out" | tr -d ' ') lines"
}

echo "input: $(wc -c < "$DIR/text" | tr -d ' ') bytes, $(wc -l < "$DIR/text" | tr -d ' ') lines"
for p in 'kappa lambda mu' '^alpha.*mu$' 'eta.*iota.*kappa' 'zzz'; do
    echo "pattern '$p'"
    echo "  minigrep: $(best_of "$DIR/minigrep" "$p" "$DIR/text")"
    echo "  grep:     $(LC_ALL=C best_of grep -- "$p" "$DIR/text")"
done
