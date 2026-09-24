#!/bin/sh
# tailcalls.sh -- build counter's IR at -O0, -O1, and -O2 and run each on 1 MB
# and 10 MB of input. Every loop in L0 is recursion, and section 8 leaves
# tail-call elimination unspecified, so whether a long-running loop survives
# depends on the optimizer rather than on the program. `tools/l0 build`
# uses -O2.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/counter.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

if [ -n "${L0_CC:-}" ]; then cc=$L0_CC
elif [ -x /opt/homebrew/opt/llvm/bin/clang ]; then cc=/opt/homebrew/opt/llvm/bin/clang
else cc=clang; fi

"$root/tools/l0" emit "$here/counter.l0" > "$tmp/counter.ll"
for opt in -O0 -O1 -O2; do
    "$cc" $opt -Wno-override-module "$tmp/counter.ll" "$root/lib/libl0rt.a" \
        -o "$tmp/counter$opt"
done

echo "| input | -O0 | -O1 | -O2 |"
echo "| --- | --- | --- | --- |"
for mb in 1 10; do
    "$here/../common/genlines.sh" "$mb" noid > "$tmp/in"
    row="| $mb MB |"
    for opt in -O0 -O1 -O2; do
        if "$tmp/counter$opt" < "$tmp/in" > /dev/null 2> "$tmp/err"; then
            row="$row ok |"
        else
            row="$row exit $?: $(cat "$tmp/err") |"
        fi
    done
    echo "$row"
done
