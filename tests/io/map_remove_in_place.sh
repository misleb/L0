#!/bin/sh
# map_remove_in_place.sh EXE -- a 1,000-key window slid over 200,000 keys
# by map_put and map_remove: the right keys and values are left, and
# L0_ARRAY_STATS reports no copies. A removal that reads the marks array
# after updating it in the same call would copy it on every shift.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
err=$(mktemp "$(dirname "$exe")/map_remove_in_place.XXXXXX")
trap 'rm -f "$err"' EXIT
got=$(L0_ARRAY_STATS=1 "$exe" 2> "$err") || fail "exited $?: $(cat "$err")"
[ "$got" = "1000
398999000
yes
no" ] || fail "printed: $got"
grep -qx 'l0: array copies: 0' "$err" || fail "an update copied: $(cat "$err")"
