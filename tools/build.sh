#!/bin/sh
# Builds the runtime and the stage-0 interpreter into build/.
#
# Usage: tools/build.sh
#
# The runtime compiled programs link is LLVM IR in two files, spec section
# 10.3: runtime/l0rt.ll, and the host file runtime/host-libc.ll, the only
# one that calls libc. They are assembled here into build/l0rt.o and
# build/l0host.o as bitcode (-flto), so that every link, which also passes
# -flto, optimizes a program and the runtime together and can inline head,
# tail, is_empty, and the counting into the program. Each is assembled a
# second time, into build/l0rt-native.o and build/l0host-native.o as machine
# code, for the quick -O0 links of tools/compiler.sh: a bitcode object makes
# even an -O0 link run LTO, ten times slower, and GNU ld takes one only with
# -flto. The only C in the repository is the stage-0 interpreter,
# stage0/l0i.c and stage0/l0core.c, built only if stage0/ is present.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"

mkdir -p "$BUILD"

CFLAGS="-std=c11 -O2 -Wall -Wextra -Wpedantic -Werror"

echo "ll  runtime/l0rt.ll runtime/host-libc.ll"
"$CC" -O2 -flto -Wno-override-module -c "$ROOT/runtime/l0rt.ll" -o "$BUILD/l0rt.o"
"$CC" -O2 -Wno-override-module -c "$ROOT/runtime/l0rt.ll" -o "$BUILD/l0rt-native.o"
"$CC" -O2 -flto -Wno-override-module -c "$ROOT/runtime/host-libc.ll" -o "$BUILD/l0host.o"
"$CC" -O2 -Wno-override-module -c "$ROOT/runtime/host-libc.ll" -o "$BUILD/l0host-native.o"

# The runtimes of the targets without libc, one for each manifest in
# runtime/targets (tools/targets.sh), as tools/install.sh installs them, in
# build/NAME, for tools/test.sh --virt and tools/bootstrap.sh --virt: each
# rebuilt when its sources are newer, and left out, with clang's complaint
# in build/NAME.err, when clang cannot build it.
. "$ROOT/tools/targets.sh"
for t in $(target_names); do
    if target_stale "$t" "$BUILD/$t"; then
        if target_runtime "$t" "$BUILD/$t"; then
            echo "ll  runtime/targets/$t.target: $T_PARTS"
        else
            echo "--  runtime/targets/$t.target: not built; see build/$t.err"
        fi
    fi
done
rm -rf "$BUILD/virt" "$BUILD/proc"

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
