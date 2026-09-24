#!/bin/sh
# Builds linediff and times it on two generated files of LINES lines, the
# second with PERCENT% of its lines replaced. Checks that the output is an
# edit script from the first file to the second, and that it is as short as
# the system diff's. Run from anywhere:
#
#   programs/linediff/bench.sh [LINES] [PERCENT]      default 5000 1
#
# Generated inputs go in a temporary directory and are deleted afterward.

set -eu

LINES=${1:-5000}
PERCENT=${2:-1}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=$(mktemp -d "${TMPDIR:-/tmp}/l0diff.XXXXXX")
trap 'rm -rf "$DIR"' EXIT

"$ROOT/tools/l0" build "$ROOT/programs/linediff/linediff.l0" \
    "$ROOT/programs/linediff/linediff_main.l0" -o "$DIR/linediff"

# Lines of three to eight random words from a small vocabulary, so that
# some lines repeat, as they do in real files.
awk -v n="$LINES" 'BEGIN {
    srand(1)
    split("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu", w, " ")
    for (i = 0; i < n; i++) {
        k = 3 + int(rand() * 6); s = ""
        for (j = 0; j < k; j++) s = s (j ? " " : "") w[1 + int(rand() * 12)]
        print s
    }
}' > "$DIR/a"
awk -v p="$PERCENT" 'BEGIN { srand(2) } {
    if (rand() * 100 < p) print "changed " NR " " int(rand() * 1000000); else print
}' "$DIR/a" > "$DIR/b"

best=""
for i in 1 2 3; do
    set +e
    /usr/bin/time -l "$DIR/linediff" "$DIR/a" "$DIR/b" > "$DIR/out" 2> "$DIR/time"
    st=$?
    set -e
    r=$(awk '/ real / {print $1}' "$DIR/time")
    m=$(awk '/maximum resident/ {print int($1 / 1024)}' "$DIR/time")
    if [ -z "$best" ] || [ "$(echo "$r < $best" | bc)" = 1 ]; then best=$r; fi
done

sed -n 's/^[ -]//p' "$DIR/out" | cmp - "$DIR/a" && echo "old side of the script is A"
sed -n 's/^[ +]//p' "$DIR/out" | cmp - "$DIR/b" && echo "new side of the script is B"
ours=$(grep -c '^[-+]' "$DIR/out" || true)
theirs=$(diff "$DIR/a" "$DIR/b" | grep -c '^[<>]' || true)
echo "lines: $LINES each; changed lines in script: ours $ours, system diff $theirs; exit $st"
echo "linediff: ${best}s, ${m} KB peak"
