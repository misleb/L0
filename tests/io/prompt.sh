#!/bin/sh
# prompt.sh EXE -- the question must be on standard output before the answer
# is sent, and the greeting must use the answer.
#
# The answer is written only after the whole question has been read back, so
# a program that waits for input before writing its question would wait
# forever. A watchdog kills it after 5 seconds, which turns that into a
# failure rather than a hang.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/prompt.XXXXXX")
trap 'rm -rf "$d"' EXIT
mkfifo "$d/in" "$d/out"

"$exe" < "$d/in" > "$d/out" &
prog=$!
( sleep 5; kill "$prog" 2> /dev/null ) &
dog=$!

exec 3> "$d/in"
exec 4< "$d/out"

question=$(dd bs=1 count=19 <&4 2> /dev/null)
if [ "$question" != "What is your name? " ]; then
    echo "expected the question before any input was sent; got '$question'"
    exit 1
fi

printf 'Ada\n' >&3
exec 3>&-
rest=$(cat <&4)
exec 4<&-
kill "$dog" 2> /dev/null || true

if ! wait "$prog"; then
    echo "the program did not exit 0"
    exit 1
fi
if [ "$rest" != "Hello, Ada!" ]; then
    echo "expected 'Hello, Ada!' after the answer; got '$rest'"
    exit 1
fi
