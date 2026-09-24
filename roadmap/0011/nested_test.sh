#!/bin/sh
# The nested case: does turning self-recursion into a loop leak stack when an
# if's alloca join slot sits inside the loop body? Compares allocas hoisted
# to the entry block (loop) against allocas left in place (loopnh).
#
# Usage: experiments/tailcalls/nested_test.sh   (after build_cases.sh)
set -u
X=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$X/../.." && pwd)
CC=/opt/homebrew/opt/llvm/bin/clang
cd "$X/out"
for v in base tail loop loopnh; do
    case $v in
        base) f="" ;;
        tail) f="--ret-direct --tail" ;;
        loop) f="--ret-direct --selfloop" ;;
        loopnh) f="--ret-direct --selfloop --no-hoist" ;;
    esac
    # shellcheck disable=SC2086
    python3 "$X/tailify.py" $f < nested.ll > nested.$v.ll
    for o in 0 2; do
        $CC -O$o -Wno-override-module nested.$v.ll "$ROOT/build/l0rt.o" -o nested.$v.O$o
        printf 'nested %-7s -O%s: %s\n' $v $o "$("$X/depth.sh" ./nested.$v.O$o 100000000)"
    done
done
