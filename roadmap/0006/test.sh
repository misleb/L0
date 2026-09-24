#!/bin/sh
# test.sh -- build linefilter and counter and compare each against its
# committed test/expected.txt, which grep and awk produced, not L0.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/programs.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail=0
for p in linefilter counter; do
    "$root/tools/l0" build "$here/$p/$p.l0" -o "$tmp/$p"
    "$tmp/$p" < "$here/$p/test/input.txt" > "$tmp/$p.out"
    if cmp -s "$tmp/$p.out" "$here/$p/test/expected.txt"; then
        echo "pass  $p"
    else
        echo "FAIL  $p"
        diff "$here/$p/test/expected.txt" "$tmp/$p.out" || true
        fail=1
    fi
done
exit $fail
