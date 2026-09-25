#!/bin/sh
# result_lost.sh EXE -- a main that takes its input, and so cannot check
# that its result was written, exits 70 when it was not.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/result_lost.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }
run() {
    set +e
    "$@" 2> "$d/err"
    st=$?
    set -e
}

# One write of the result, and then many, since the runtime writes it in
# 64 KB pieces.
printf 'hi\n' > "$d/small"
head -c 200000 /dev/urandom > "$d/big"
for f in small big; do
    run "$exe" < "$d/$f" > "$d/out"
    [ "$st" = 0 ] || fail "$f exited $st: $(cat "$d/err")"
    cmp -s "$d/$f" "$d/out" || fail "$f: the result differs from the input"

    run "$exe" < "$d/$f" >&-
    [ "$st" = 70 ] || fail "$f, standard output closed, exited $st, not 70"
    [ "$(cat "$d/err")" = "l0: runtime error: write failed" ] ||
        fail "$f, standard output closed: $(cat "$d/err")"
done
