#!/bin/sh
# array_through.sh EXE -- each mode of array_through.l0, 300,000 steps over
# three elements, with L0_ARRAY_STATS and L0_RC_CHECK: the result, how many
# updates copied, and that nothing was left live or used once freed. Before
# spec 6.5 took the element out for the function, through copied a context
# per step, as mentions still does.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
err=$(mktemp "$(dirname "$exe")/array_through.XXXXXX")
trap 'rm -f "$err"' EXIT

check() {
    mode=$1 want=$2 copies=$3
    got=$(L0_ARRAY_STATS=1 L0_RC_CHECK=1 "$exe" "$mode" 300000 2> "$err") ||
        fail "$mode exited $?: $(cat "$err")"
    [ "$got" = "$want" ] || fail "$mode gave $got, not $want"
    grep -qx "l0: array copies: $copies" "$err" ||
        fail "$mode did not copy $copies times: $(cat "$err")"
    if grep -q 'still live' "$err"; then fail "$mode left blocks live: $(cat "$err")"; fi
}

check through 300000 0
check list 300000 0
check shared 300000 4
check mentions 900000 300000
