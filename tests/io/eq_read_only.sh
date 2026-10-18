#!/bin/sh
# eq_read_only.sh EXE IR -- a loop whose bytes parameters are used only by
# eq is a tail call that increments and decrements nothing, and compares
# them in the runtime (spec 10.3).
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
status=0
L0_RC_CHECK=1 "$exe" || status=$?
[ "$status" = 3 ] || fail "exited $status, not 3"
body=$(awk '/^define .*@l0_f_count_same\(/,/^}/' "$ir")
[ -n "$body" ] || fail "no count_same in the IR"
echo "$body" | grep -q 'musttail call fastcc i64 @l0_f_count_same(' || fail "not a tail call"
echo "$body" | grep -q 'call i64 @l0_equal(' || fail "eq on bytes is not a runtime call"
echo "$body" | grep -Eq 'call void @l0_(inc|dec)\(' && fail "counts references"
exit 0
