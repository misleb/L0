#!/bin/sh
# bytes_read_failure.sh EXE IR -- standard input is a directory, which opens
# but cannot be read, so read_bytes gives nothing and read_from then gives -5.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
status=0
L0_RC_CHECK=1 "$exe" < "$(dirname "$0")" || status=$?
[ "$status" = 55 ] || fail "exited $status, not 55"
exit 0
