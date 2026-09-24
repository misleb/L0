#!/bin/sh
# Relinks the compiled suite's leftover IR against proto-rt.ll, with no C
# objects, and judges each program against the same expectation files.
# Run tools/test.sh --compiled first: it leaves the IR in build/test-tmp.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CC=${CC:-/opt/homebrew/opt/llvm/bin/clang}
P=$(cd "$(dirname "$0")" && pwd)
T="$ROOT/build/proto-tmp"
mkdir -p "$T"
pass=0; fail=0
for ll in "$ROOT"/build/test-tmp/*.ll; do
    name=$(basename "$ll" .ll)
    if [ -f "$ROOT/tests/lang/$name.l0" ]; then stem="$ROOT/tests/lang/$name"
    elif [ -f "$ROOT/tests/compiler/$name.l0" ]; then stem="$ROOT/tests/compiler/$name"
    else continue; fi
    awk 'BEGIN { print "declare void @l0_stack_check()" }
         { print }
         /^define .*@l0_[fp]_/ { indef = 1; next }
         indef && /^entry:$/ { print "  call void @l0_stack_check()"; indef = 0 }' \
        "$ll" > "$T/$name.ll"
    if ! "$CC" -O2 -Wno-override-module "$T/$name.ll" "$P/proto-rt.ll" \
        -o "$T/$name.exe" 2> "$T/$name.lerr"; then
        echo "FAIL $name: link"; sed 's/^/    /' "$T/$name.lerr"; fail=$((fail + 1)); continue
    fi
    in=/dev/null; [ -f "$stem.in" ] && in="$stem.in"
    "$T/$name.exe" < "$in" > "$T/$name.out" 2> "$T/$name.err"
    got=$?
    want=0; [ -f "$stem.exit" ] && want=$(cat "$stem.exit")
    why=""
    if ! cmp -s "$T/$name.out" "$stem.out"; then why="stdout differs"
    elif [ -f "$stem.err" ] && ! cmp -s "$T/$name.err" "$stem.err"; then why="stderr differs"
    elif [ ! -f "$stem.err" ] && [ -s "$T/$name.err" ]; then why="unexpected stderr"
    elif [ "$got" != "$want" ]; then why="exit $got, want $want"; fi
    if [ -z "$why" ]; then pass=$((pass + 1)); else echo "FAIL $name: $why"; fail=$((fail + 1)); fi
done
echo "proto runtime: $pass passed, $fail failed"
