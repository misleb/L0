#!/bin/sh
# args.sh EXE -- arguments arrive as given, one per call to arg, including one
# with a space and one that is empty, and the program's own name is not one.
set -eu
exe=$1
got=$("$exe" one "two words" "")
want=$(printf '3\n[one]\n[two words]\n[]\npast the end: []\nnegative: []')
if [ "$got" != "$want" ]; then
    echo "expected:"; echo "$want"; echo "got:"; echo "$got"
    exit 1
fi
none=$("$exe")
[ "$none" = "$(printf '0\npast the end: []\nnegative: []')" ] ||
    { echo "with no arguments, got: $none"; exit 1; }
