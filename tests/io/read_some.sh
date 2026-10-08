#!/bin/sh
# read_some.sh EXE IR -- spec 6.6's read_some, through file_read_some: a file
# of about 1.3 MB copied whole in pieces of at most 1000 bytes, and in pieces
# no larger than the handle's buffer however large n is; the same through a
# pipe; and a directory as standard input, which fails rather than ending.
# L0_RC_CHECK shows every piece is freed.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/read_some.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }

awk 'BEGIN { for (i = 0; i < 200000; i++) printf "%d\n", i }' > "$d/in"
size=$(wc -c < "$d/in" | tr -d ' ')

L0_RC_CHECK=1 "$exe" 1000 < "$d/in" > "$d/out" 2> "$d/err" || fail "file: exited $?: $(cat "$d/err")"
cmp -s "$d/in" "$d/out" || fail "file: the copy differs"
# At most 1000 a piece, and shorter where the handle's buffer runs out.
[ "$(cat "$d/err")" -ge $(( (size + 999) / 1000 )) ] || fail "file: only $(cat "$d/err") pieces"

L0_RC_CHECK=1 "$exe" 100000000 < "$d/in" > "$d/out" 2> "$d/err" || fail "large n: exited $?"
cmp -s "$d/in" "$d/out" || fail "large n: the copy differs"
[ "$(cat "$d/err")" -ge $(( size / 65536 )) ] || fail "large n: only $(cat "$d/err") pieces"

cat "$d/in" | L0_RC_CHECK=1 "$exe" 4096 > "$d/out" 2> "$d/err" || fail "pipe: exited $?"
cmp -s "$d/in" "$d/out" || fail "pipe: the copy differs"

st=0
"$exe" 1000 < "$(dirname "$0")" > "$d/out" 2> "$d/err" || st=$?
[ "$st" = 2 ] || fail "directory: exited $st"
[ "$(cat "$d/err")" = "failed: input or output failed" ] || fail "directory: $(cat "$d/err")"
