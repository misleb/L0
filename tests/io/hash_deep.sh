#!/bin/sh
# hash_deep.sh EXE IR -- spec 6.9: hash answers on a million-element list,
# an array of long lists, and a value nested 100,000 deep on a 1 MB stack,
# which holds about fifteen thousand frames, so its walk cannot be
# recursing. Equal values hash alike, and these unequal ones, by the spec's
# definition, do not. L0_RC_CHECK shows it neither consumes nor leaks what
# it hashes.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
want=$(printf 'true\nfalse\ntrue\ntrue\nfalse')
got=$(L0_STACK_MB=1 L0_RC_CHECK=1 "$exe" 2>&1) || fail "failed: $got"
[ "$got" = "$want" ] || fail "expected: $want
got: $got"
exit 0
