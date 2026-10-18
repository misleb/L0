#!/bin/sh
# bytes_read_only.sh EXE IR -- a loop over a read-only bytes parameter is a
# tail call that increments and decrements nothing (spec 10.3).
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
status=0
L0_RC_CHECK=1 "$exe" || status=$?
[ "$status" = 3 ] || fail "exited $status, not 3"
body=$(awk '/^define .*@l0_f_sum_from\(/,/^}/' "$ir")
[ -n "$body" ] || fail "no sum_from in the IR"
echo "$body" | grep -q 'musttail call fastcc i64 @l0_f_sum_from(' || fail "not a tail call"
echo "$body" | grep -Eq 'call void @l0_(inc|dec)\(' && fail "counts references"
exit 0
