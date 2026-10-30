#!/bin/sh
# fields_in_place.sh EXE -- each mode of fields_in_place.l0, 100,000 steps
# over a three-field record, with L0_ARRAY_STATS and L0_RC_CHECK: the
# result, how many replacements copied, and that nothing was left live or
# used once freed.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
err=$(mktemp "$(dirname "$exe")/fields_in_place.XXXXXX")
trap 'rm -f "$err"' EXIT

check() {
    mode=$1 want=$2 copies=$3
    got=$(L0_ARRAY_STATS=1 L0_RC_CHECK=1 "$exe" "$mode" 100000 2> "$err") ||
        fail "$mode exited $?: $(cat "$err")"
    [ "$got" = "$want" ] || fail "$mode gave $got, not $want"
    grep -qx "l0: array copies: $copies" "$err" ||
        fail "$mode did not copy $copies times: $(cat "$err")"
    if grep -q 'still live' "$err"; then fail "$mode left blocks live: $(cat "$err")"; fi
}

check alone 200000 0
check shared 200000 1
check late 199999 100000
check through 200000 0
