#!/bin/sh
# bytes_slice_read_only.sh EXE IR -- loops that slice a read-only bytes
# parameter and join a read-only list of bytes are tail calls that
# increment and decrement nothing, and leak nothing (spec 10.3).
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
status=0
err=$(L0_RC_CHECK=1 "$exe" 2>&1 >/dev/null) || status=$?
[ "$status" = 3 ] || fail "exited $status, not 3: $err"
[ -z "$err" ] || fail "wrote on standard error: $err"
for f in sum_slices sum_joins; do
  body=$(awk "/^define .*@l0_f_$f\\(/,/^}/" "$ir")
  [ -n "$body" ] || fail "no $f in the IR"
  echo "$body" | grep -q "musttail call fastcc i64 @l0_f_$f(" || fail "$f is not a tail call"
  echo "$body" | grep -Eq 'call void @l0_inc\(' && fail "$f increments"
  echo "$body" | grep -q 'call i64 @l0_bytes_' || fail "$f calls no bytes builtin"
done
exit 0
