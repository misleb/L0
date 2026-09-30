#!/bin/sh
# clock.sh EXE IR -- the input is sent a second after the program says it is
# ready, which it does after its first reading of clock_ns, so its readings
# either side of the read that waits must differ by at least that second.
#
# The second starts only once "ready" has been read back, since a freshly
# built program can take longer than that to start; a watchdog kills it after
# 30 seconds, which turns a hang into a failure.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/clock.XXXXXX")
trap 'rm -rf "$d"' EXIT
mkfifo "$d/in" "$d/out"

L0_RC_CHECK=1 "$exe" < "$d/in" > "$d/out" 2>&1 &
prog=$!
( sleep 30; kill "$prog" 2> /dev/null ) &
dog=$!

exec 3> "$d/in"
exec 4< "$d/out"

ready=$(dd bs=1 count=6 <&4 2> /dev/null)
if [ "$ready" != "ready" ]; then
    echo "expected 'ready' first; got '$ready'"
    exit 1
fi

sleep 1
printf 'x\n' >&3
exec 3>&-
rest=$(cat <&4)
exec 4<&-
kill "$dog" 2> /dev/null || true

status=0
wait "$prog" || status=$?
if [ "$status" != 0 ] || [ "$rest" != "ok" ]; then
    echo "exited $status: $rest"
    exit 1
fi
