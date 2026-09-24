#!/bin/sh
# filecopy.sh EXE -- copies a file named on the command line exactly, and
# reports each kind of failure on standard error with the right status.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/filecopy.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }

# Larger than the runtime's 64 KB buffers, so they fill and refill, and
# random, so every byte value appears.
head -c 300000 /dev/urandom > "$d/in"
"$exe" "$d/in" "$d/out" || fail "a plain copy exited $?"
cmp -s "$d/in" "$d/out" || fail "the copy differs from the original"

printf 'short' > "$d/small"
"$exe" "$d/small" "$d/out" || fail "copying over an existing file exited $?"
[ "$(cat "$d/out")" = short ] || fail "an existing destination was not emptied first"

run() {
    set +e
    "$@" 2> "$d/err"
    st=$?
    set -e
}

run "$exe" "$d/missing" "$d/out2"
[ "$st" = 1 ] || fail "a missing source exited $st, not 1"
[ "$(cat "$d/err")" = "filecopy: $d/missing: no such file" ] ||
    fail "for a missing source: $(cat "$d/err")"
[ ! -e "$d/out2" ] || fail "a destination was created for a missing source"

run "$exe" "$d/small" "$d/nodir/out"
[ "$st" = 1 ] || fail "an unwritable destination exited $st, not 1"
[ "$(cat "$d/err")" = "filecopy: $d/nodir/out: input or output failed" ] ||
    fail "for an unwritable destination: $(cat "$d/err")"

run "$exe" only-one
[ "$st" = 2 ] || fail "a usage error exited $st, not 2"
[ "$(cat "$d/err")" = "usage: filecopy FROM TO" ] ||
    fail "for a usage error: $(cat "$d/err")"

# Permission bits stop neither root nor every filesystem, Docker's bind
# mounts among them, so this case is checked only where they are enforced.
printf 'x' > "$d/secret"
chmod 000 "$d/secret"
if cat "$d/secret" > /dev/null 2>&1; then
    chmod 600 "$d/secret"
else
    run "$exe" "$d/secret" "$d/out3"
    chmod 600 "$d/secret"
    [ "$st" = 1 ] || fail "an unreadable source exited $st, not 1"
    [ "$(cat "$d/err")" = "filecopy: $d/secret: permission denied" ] ||
        fail "for an unreadable source: $(cat "$d/err")"
fi
