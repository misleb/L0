#!/bin/sh
# shadow_row.sh EXE IR -- spec 6.5's nested update, with array_get the
# program's own (spec 7): a call of the program's function, and no
# l0_array_set_row, which would skip it.
set -eu
exe=$1
ir=$2
fail() { echo "$*"; exit 1; }
L0_RC_CHECK=1 "$exe" || fail "exited $?"
grep -q 'call i64 @l0_array_set_row' "$ir" && fail "compiled as the builtin's nested update"
grep -q 'call fastcc i64 @l0_f_array_get(' "$ir" || fail "no call of the program's array_get"
exit 0
