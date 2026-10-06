#!/bin/sh
# hash_read_only.sh EXE IR -- a loop whose bytes parameter is used only by
# hash is a tail call that increments and decrements nothing, and hashes it
# in the runtime, told it is counted (spec 10.3).
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
status=0
L0_RC_CHECK=1 "$exe" || status=$?
[ "$status" = 3 ] || fail "exited $status, not 3"
body=$(awk '/^define .*@l0_f_sum_hashes\(/,/^}/' "$ir")
[ -n "$body" ] || fail "no sum_hashes in the IR"
echo "$body" | grep -q 'musttail call i64 @l0_f_sum_hashes(' || fail "not a tail call"
echo "$body" | grep -q 'call i64 @l0_hash(i64 %[a-z0-9.]*, i64 1)' ||
    fail "hash of bytes is not a runtime call told it is counted"
echo "$body" | grep -Eq 'call void @l0_(inc|dec)\(' && fail "counts references"
exit 0
