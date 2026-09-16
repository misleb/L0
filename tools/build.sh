#!/bin/sh
# Builds the runtime objects and the stage-0 interpreter into build/.
#
# Usage: tools/build.sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"

mkdir -p "$BUILD"

CFLAGS="-std=c11 -O2 -Wall -Wextra -Wpedantic -Werror"

echo "cc  runtime/l0core.c"
"$CC" $CFLAGS -I"$ROOT/runtime" -c "$ROOT/runtime/l0core.c" -o "$BUILD/l0core.o"

echo "cc  runtime/l0rt.c"
"$CC" $CFLAGS -I"$ROOT/runtime" -c "$ROOT/runtime/l0rt.c" -o "$BUILD/l0rt.o"

echo "cc  stage0/l0i.c"
"$CC" $CFLAGS -I"$ROOT/runtime" "$ROOT/stage0/l0i.c" "$BUILD/l0core.o" \
    -o "$BUILD/l0i"

echo "ok  build/l0i"
