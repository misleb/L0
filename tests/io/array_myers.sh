#!/bin/sh
# array_myers.sh EXE -- the vector sweep gives the same sum as the same
# recurrence in awk, and every one of its millions of updates happened in
# place: L0_ARRAY_STATS reports no copies.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
D=2000

want=$(awk -v D=$D 'BEGIN { for (i = 0; i <= D; i++) v[i] = 0
        for (d = 1; d <= D; d++)
            for (j = d; j >= 1; j--) { x = v[j-1] + 1; if (x > v[j]) v[j] = x }
        s = 0; for (i = 0; i <= D; i++) s += v[i]; print s }')
err=$(mktemp "$(dirname "$exe")/array_myers.XXXXXX")
trap 'rm -f "$err"' EXIT
got=$(L0_ARRAY_STATS=1 "$exe" $D sum 2> "$err") || fail "exited $?: $(cat "$err")"
[ "$got" = "$want" ] || fail "sum $got, not $want"
grep -qx 'l0: array copies: 0' "$err" || fail "an update copied: $(cat "$err")"
