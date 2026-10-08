#!/bin/sh
# compare_read_only.sh EXE IR -- a loop whose list parameters are used only
# by compare is a tail call that increments and decrements nothing, orders
# the lists in the runtime, and orders its ints with instructions (spec 10.3).
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
status=0
L0_RC_CHECK=1 "$exe" || status=$?
[ "$status" = 3 ] || fail "exited $status, not 3"
body=$(awk '/^define .*@l0_f_count_before\(/,/^}/' "$ir")
[ -n "$body" ] || fail "no count_before in the IR"
echo "$body" | grep -q 'musttail call i64 @l0_f_count_before(' || fail "not a tail call"
[ "$(echo "$body" | grep -c 'call i64 @l0_compare(')" = 1 ] ||
    fail "not exactly one runtime compare, for the lists"
echo "$body" | grep -q 'icmp sgt' || fail "compare on ints is not instructions"
echo "$body" | grep -Eq 'call void @l0_(inc|dec)\(' && fail "counts references"
exit 0
