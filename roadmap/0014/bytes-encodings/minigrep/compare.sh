#!/bin/sh
# Differential test of minigrep against the system grep: random patterns
# over the alphabet a b . * with random anchors, against a file of random
# short lines of a and b. Also checks the exit statuses. Run from anywhere:
#
#   programs/minigrep/compare.sh [PATTERNS]         default 500

set -eu

RUNS=${1:-500}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=$(mktemp -d "${TMPDIR:-/tmp}/l0grep.XXXXXX")
trap 'rm -rf "$DIR"' EXIT

"$ROOT/tools/l0" build "$ROOT/programs/minigrep/minigrep.l0" \
    "$ROOT/programs/minigrep/minigrep_main.l0" -o "$DIR/minigrep"

awk 'BEGIN { srand(3); for (i = 0; i < 300; i++) {
    n = int(rand() * 8); s = ""
    for (j = 0; j < n; j++) s = s (rand() < 0.5 ? "a" : "b")
    print s } }' > "$DIR/lines"
awk -v runs="$RUNS" 'BEGIN { srand(4); split("a b . *", c, " ")
    for (i = 0; i < runs; i++) {
        n = 1 + int(rand() * 5); s = (rand() < 0.3 ? "^" : "")
        for (j = 0; j < n; j++) s = s c[1 + int(rand() * 4)]
        if (rand() < 0.3) s = s "$"
        print s } }' > "$DIR/patterns"

# BSD grep, which macOS has, rejects a repeated * as invalid; GNU grep and
# minigrep treat ** as *. Those patterns are counted and skipped.
bad=0
rejected=0
while IFS= read -r p; do
    set +e
    "$DIR/minigrep" "$p" "$DIR/lines" | sed "s|^$DIR/lines:||" > "$DIR/ours"
    LC_ALL=C grep -- "$p" "$DIR/lines" > "$DIR/theirs" 2> /dev/null
    theirs=$?
    set -e
    if [ "$theirs" = 2 ]; then
        rejected=$((rejected + 1))
    elif ! cmp -s "$DIR/ours" "$DIR/theirs"; then
        echo "DIFFERENT output for pattern '$p'"
        bad=$((bad + 1))
    fi
done < "$DIR/patterns"

set +e
"$DIR/minigrep" 'zzz' "$DIR/lines" > /dev/null; s1=$?
"$DIR/minigrep" 'a' "$DIR/lines" > /dev/null; s0=$?
"$DIR/minigrep" 'a' "$DIR/lines" "$DIR/missing" > /dev/null 2>&1; s2=$?
"$DIR/minigrep" 'a' > /dev/null 2>&1; su=$?
set -e
echo "exit statuses: match $s0, no match $s1, missing file $s2, usage $su (want 0 1 2 2)"
echo "$RUNS patterns: $rejected rejected by system grep, $bad of the rest differ"
[ "$bad" = 0 ]
