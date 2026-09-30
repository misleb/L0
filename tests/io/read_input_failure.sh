#!/bin/sh
# read_input_failure.sh EXE IR -- standard input is a directory, which opens
# but cannot be read, so read_input gives IoReadFailed.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
status=0
err=$(L0_RC_CHECK=1 "$exe" < "$(dirname "$0")" 2>&1) || status=$?
[ "$status" = 3 ] || fail "exited $status, not 3: $err"
[ "$err" = "failed: input or output failed" ] || fail "said: $err"
exit 0
