#!/bin/sh
# parametric_fn_names.sh EXE IR -- a function with type parameters compiles
# to one copy per combination of counted and not, named with one digit per
# type parameter, and each call reaches the copy its arguments choose
# (spec 10.2).
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
out=$("$exe" < /dev/null) || fail "exited $?"
[ "$out" = "121" ] || fail "printed $out, not 121"
grep -q '^define internal i64 @l0_f_keep_first\.00(' "$ir" ||
    fail "no copy keep_first.00"
grep -q '^define internal i64 @l0_f_keep_first\.10(' "$ir" ||
    fail "no copy keep_first.10"
calls=$(awk '/^define internal i64 @l0_f_main\.body\(/,/^}/' "$ir" |
    grep -o '@l0_f_keep_first\.[01]*' | tr '\n' ' ')
[ "$calls" = "@l0_f_keep_first.00 @l0_f_keep_first.10 " ] ||
    fail "main calls $calls"
