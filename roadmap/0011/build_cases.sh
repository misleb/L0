#!/bin/sh
# Check and emit every case with the current compiler, then link each at
# -O0, -O1 and -O2 with Homebrew clang (what tools/l0ll uses) and Apple clang.
# Output goes to experiments/tailcalls/out/, which is not committed.
#
# Usage: experiments/tailcalls/build_cases.sh   (from the repository root,
#        after tools/bootstrap.sh and cp build/stage2 build/l0c-native)
set -eu
ROOT=$(pwd)
X=experiments/tailcalls
OUT=$X/out
mkdir -p "$OUT"
BREW=/opt/homebrew/opt/llvm/bin/clang
APPLE=/usr/bin/clang
export L0_COMPILER="$ROOT/build/l0c-native" L0_RUNTIME="$ROOT/build/l0rt.o"
for f in $X/cases/*.l0; do
    n=$(basename "$f" .l0)
    tools/l0 check "$f" > /dev/null
    tools/l0 emit "$f" > "$OUT/$n.ll"
    for o in 0 1 2; do
        "$BREW" -O$o -Wno-override-module "$OUT/$n.ll" build/l0rt.o -o "$OUT/$n.brew.O$o"
        "$APPLE" -O$o -Wno-override-module "$OUT/$n.ll" build/l0rt.o -o "$OUT/$n.apple.O$o" 2>/dev/null ||
            echo "apple clang cannot read $n.ll at -O$o" >&2
    done
    # Every function noinline: a model of a program large enough that its
    # recursive functions are not inlined into their callers.
    python3 $X/tailify.py --noinline < "$OUT/$n.ll" > "$OUT/$n.noinl.ll"
    "$BREW" -O2 -Wno-override-module "$OUT/$n.noinl.ll" build/l0rt.o -o "$OUT/$n.noinl.brew.O2"
    "$APPLE" -O2 -Wno-override-module "$OUT/$n.noinl.ll" build/l0rt.o -o "$OUT/$n.noinl.apple.O2"
    "$BREW" -O2 -S -Wno-override-module "$OUT/$n.noinl.ll" -o "$OUT/$n.noinl.O2.s"
    "$APPLE" -O2 -S -Wno-override-module "$OUT/$n.noinl.ll" -o "$OUT/$n.noinl.apple.O2.s"
    "$BREW" -O1 -S -Wno-override-module "$OUT/$n.ll" -o "$OUT/$n.O1.s"
    "$BREW" -O2 -S -emit-llvm -Wno-override-module "$OUT/$n.ll" -o "$OUT/$n.opt.ll"
    "$BREW" -O2 -S -Wno-override-module "$OUT/$n.ll" -o "$OUT/$n.O2.s"
    "$BREW" -O0 -S -Wno-override-module "$OUT/$n.ll" -o "$OUT/$n.O0.s"
    echo "built $n"
done
