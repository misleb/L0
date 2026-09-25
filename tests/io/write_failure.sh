#!/bin/sh
# write_failure.sh EXE -- a write that fails is reported: by flush, to a
# program that looks, and by the host as a runtime error, to one that does
# not. >&- closes standard output, which makes every write to it fail on
# macOS and Linux alike; /dev/full, where there is one, fails it for want of
# space instead.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/write_failure.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }
run() {
    set +e
    "$@" 2> "$d/err"
    st=$?
    set -e
}
size() { wc -c < "$1" | tr -d ' '; }

run "$exe" checked >&-
[ "$st" = 1 ] || fail "checked, standard output closed, exited $st, not 1"
[ "$(cat "$d/err")" = "write_failure: write error" ] ||
    fail "checked, standard output closed: $(cat "$d/err")"

run "$exe" checked > "$d/out"
[ "$st" = 0 ] || fail "checked exited $st: $(cat "$d/err")"
[ "$(size "$d/out")" = 200000 ] || fail "checked wrote $(size "$d/out") bytes"

run "$exe" unchecked >&-
[ "$st" = 70 ] || fail "unchecked, standard output closed, exited $st, not 70"
[ "$(cat "$d/err")" = "l0: runtime error: write failed" ] ||
    fail "unchecked, standard output closed: $(cat "$d/err")"

run "$exe" unchecked > "$d/out"
[ "$st" = 0 ] || fail "unchecked exited $st: $(cat "$d/err")"
[ "$(size "$d/out")" = 200000 ] || fail "unchecked wrote $(size "$d/out") bytes"
[ ! -s "$d/err" ] || fail "unchecked wrote to standard error: $(cat "$d/err")"

# With standard error closed too, the status alone says so.
set +e
"$exe" unchecked >&- 2>&-
st=$?
set -e
[ "$st" = 70 ] || fail "unchecked, both closed, exited $st, not 70"

run "$exe" sticky >&-
[ "$st" = 3 ] || fail "sticky exited $st, not the 3 it returned"
[ "$(cat "$d/err")" = "first -5
second -5" ] || fail "sticky: $(cat "$d/err")"

run "$exe" file "$d/f" > "$d/out"
[ "$st" = 0 ] || fail "file exited $st: $(cat "$d/err")"
[ "$(cat "$d/out")" = "flush file: 0
read back: abc
flush 0: -2
flush 42: -2
flush -1: -2" ] || fail "file: $(cat "$d/out")"

if [ -w /dev/full ]; then
    run "$exe" unchecked > /dev/full
    [ "$st" = 70 ] || fail "unchecked to /dev/full exited $st, not 70"
    run "$exe" checked > /dev/full
    [ "$st" = 1 ] || fail "checked to /dev/full exited $st, not 1"
fi
