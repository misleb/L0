#!/bin/sh
# array_state.sh EXE -- a state of arrays in a data value, read through
# read-only helpers and updated where it is taken apart: 200,000 steps with
# the right totals, and L0_ARRAY_STATS reports no copies. Giving a helper
# that takes the state apart a read-only parameter would copy on every step.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
err=$(mktemp "$(dirname "$exe")/array_state.XXXXXX")
trap 'rm -f "$err"' EXIT
got=$(L0_ARRAY_STATS=1 "$exe" 2> "$err") || fail "exited $?: $(cat "$err")"
[ "$got" = "200000
200000" ] || fail "printed: $got"
grep -qx 'l0: array copies: 0' "$err" || fail "an update copied: $(cat "$err")"
