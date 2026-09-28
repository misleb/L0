#!/bin/sh
# Builds the runtime and the stage-0 interpreter into build/.
#
# Usage: tools/build.sh
#
# The runtime compiled programs link is LLVM IR, runtime/l0rt.ll, assembled
# here into build/l0rt.o as bitcode (-flto), so that every link, which also
# passes -flto, optimizes a program and the runtime together and can inline
# head, tail, is_empty, and the counting into the program. The only C in the
# repository is the stage-0
# interpreter, stage0/l0i.c and stage0/l0core.c, built only if stage0/ is
# present.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"

mkdir -p "$BUILD"

CFLAGS="-std=c11 -O2 -Wall -Wextra -Wpedantic -Werror"

echo "ll  runtime/l0rt.ll"
"$CC" -O2 -flto -Wno-override-module -c "$ROOT/runtime/l0rt.ll" -o "$BUILD/l0rt.o"

if [ -f "$ROOT/stage0/l0i.c" ]; then
    echo "cc  stage0/l0core.c"
    "$CC" $CFLAGS -I"$ROOT/stage0" -c "$ROOT/stage0/l0core.c" \
        -o "$BUILD/l0core.o"
    echo "cc  stage0/l0i.c"
    "$CC" $CFLAGS -I"$ROOT/stage0" "$ROOT/stage0/l0i.c" "$BUILD/l0core.o" \
        -o "$BUILD/l0i"
    echo "ok  build/l0i and the runtime"
else
    rm -f "$BUILD/l0i" # never leave a stale interpreter behind
    echo "ok  the runtime (stage0 is gone; bootstrap from bootstrap/stage2.ll)"
fi
