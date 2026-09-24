#!/bin/sh
# check.sh -- run tools/l0check on every .l0 file under programs/, each
# together with the prelude, and print the exact output and exit status.
# Limit 05 is also run through `tools/l0 build`, because l0check does not
# look at main's signature. The committed check.txt is this script's output.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root"

for f in programs/linefilter/*.l0 programs/counter/*.l0 \
         programs/limits/*.l0 programs/hypothetical/*.l0; do
    echo "\$ tools/l0check lib/prelude.l0 $f"
    tools/l0check lib/prelude.l0 "$f" 2>&1
    echo "exit $?"
    echo
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
f=programs/limits/05-no-command-line.l0
echo "\$ tools/l0 build $f"
tools/l0 build "$f" -o "$tmp/prog" 2>&1
echo "exit $?"
echo
echo "\$ build/l0i run lib/prelude.l0 $f < /dev/null"
build/l0i run lib/prelude.l0 "$f" < /dev/null 2>&1
echo "exit $?"
