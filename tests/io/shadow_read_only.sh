#!/bin/sh
# shadow_read_only.sh EXE -- an update through a def named array_len (spec 7)
# is in place: the parameter it escapes from is not read-only (spec 10.3).
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
err=$(mktemp "$(dirname "$exe")/shadow_read_only.XXXXXX")
trap 'rm -f "$err"' EXIT
L0_RC_CHECK=1 L0_ARRAY_STATS=1 "$exe" 2> "$err" || fail "exited $?: $(cat "$err")"
grep -qx 'l0: array copies: 0' "$err" || fail "the update copied: $(cat "$err")"
