#!/bin/sh
# broken_pipe.sh EXE -- a write to a pipe whose reader has gone is a write
# failure, never a signal (spec 6.3). A program told of it keeps its status
# and carries on; one never told exits 70. Before 0057 both were killed by
# SIGPIPE, with status 141 and the told one's FILE never written.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/broken_pipe.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }

{ st=0; "$exe" told "$d/after" 2> "$d/err" || st=$?; echo $st > "$d/status"; } |
    head -c 10 > /dev/null
[ "$(cat "$d/status")" = 3 ] || fail "told: exited $(cat "$d/status"): $(cat "$d/err")"
[ "$(cat "$d/after" 2> /dev/null)" = after ] || fail "told: FILE not written after the failure"

{ st=0; "$exe" quiet "$d/unused" 2> "$d/err" || st=$?; echo $st > "$d/status"; } |
    head -c 10 > /dev/null
[ "$(cat "$d/status")" = 70 ] || fail "quiet: exited $(cat "$d/status"): $(cat "$d/err")"
grep -q "write failed" "$d/err" || fail "quiet: no runtime error: $(cat "$d/err")"
