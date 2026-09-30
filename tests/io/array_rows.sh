#!/bin/sh
# array_rows.sh EXE -- a 1,000 by 1,000 grid of rows, a million cells set by
# the nested form: the sum of y + x over the grid, and no copy at all.
# Before spec 6.5 made the form update in place, it copied a row per cell.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
err=$(mktemp "$(dirname "$exe")/array_rows.XXXXXX")
trap 'rm -f "$err"' EXIT
got=$(L0_ARRAY_STATS=1 "$exe" 1000 2> "$err") || fail "exited $?: $(cat "$err")"
[ "$got" = 999000000 ] || fail "sum $got, not 999000000"
grep -qx 'l0: array copies: 0' "$err" || fail "an update copied: $(cat "$err")"
