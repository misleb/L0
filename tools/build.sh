#!/bin/sh
# Builds the C parts of the toolchain into build/.
#
# Usage: tools/build.sh
#
# Always builds the runtime, which is permanent. Builds the stage-0
# interpreter only if stage0/ is still present: it is deleted once
# self-compilation reaches a fixpoint, and everything here must keep working
# from a fresh clone after that happens.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"

mkdir -p "$BUILD"

CFLAGS="-std=c11 -O2 -Wall -Wextra -Wpedantic -Werror"

echo "cc  runtime/l0core.c"
"$CC" $CFLAGS -I"$ROOT/runtime" -c "$ROOT/runtime/l0core.c" -o "$BUILD/l0core.o"

echo "cc  runtime/l0rt.c"
"$CC" $CFLAGS -I"$ROOT/runtime" -c "$ROOT/runtime/l0rt.c" -o "$BUILD/l0rt.o"

if [ -f "$ROOT/stage0/l0i.c" ]; then
    echo "cc  stage0/l0i.c"
    "$CC" $CFLAGS -I"$ROOT/runtime" "$ROOT/stage0/l0i.c" "$BUILD/l0core.o" \
        -o "$BUILD/l0i"
    echo "ok  build/l0i and the runtime"
else
    rm -f "$BUILD/l0i" # never leave a stale interpreter behind
    echo "ok  the runtime (stage0 is gone; bootstrap from bootstrap/stage2.ll)"
fi
