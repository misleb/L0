#!/bin/sh
# eq_deep.sh EXE IR -- spec 6.8: eq answers on a million-element list and a
# value nested 100,000 deep on a 1 MB stack, which holds about fifteen
# thousand frames, so its walk cannot be recursing. L0_RC_CHECK shows it
# neither consumes nor leaks what it compares.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
want=$(printf 'true\nfalse\nfalse\ntrue\ntrue\nfalse')
got=$(L0_STACK_MB=1 L0_RC_CHECK=1 "$exe" 2>&1) || fail "failed: $got"
[ "$got" = "$want" ] || fail "expected: $want
got: $got"
exit 0
