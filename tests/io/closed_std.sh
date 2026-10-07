#!/bin/sh
# closed_std.sh EXE -- a standard handle the host left closed is open on
# nothing (spec 6.3): writes to it fail and are reported, reads return -5,
# and no file the program opens takes its number. Before 0057 the first file
# opened became standard output and received both lines.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/closed_std.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }

st=0
"$exe" out "$d/file" >&- 2> "$d/err" || st=$?
[ "$st" = 0 ] || fail "out: exited $st: $(cat "$d/err")"
[ "$(cat "$d/file")" = "meant for the file" ] || fail "out: FILE holds: $(cat "$d/file")"

got=$("$exe" in <&- 2>&1)
[ "$got" = -5 ] || fail "in: read_byte gave $got"
