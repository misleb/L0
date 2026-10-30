#!/bin/sh
# fmt.sh EXE -- the formatter over every .l0 file of the compiler, the
# library, and the L0 kernel, each of which must come back byte-identical.
set -eu
exe=$1
fail() { echo "$*"; exit 1; }
out=$(mktemp "$(dirname "$exe")/fmt.XXXXXX")
trap 'rm -f "$out"' EXIT
n=0
for f in compiler/*.l0 lib/*.l0 tests/virt/user/*.l0; do
    "$exe" < "$f" > "$out" || fail "$f: the formatter exited $?"
    cmp -s "$f" "$out" || fail "$f: changed by the formatter: $(diff "$f" "$out" | head -5)"
    n=$((n + 1))
done
[ "$n" -gt 10 ] || fail "only $n files found; run from the repository root"
