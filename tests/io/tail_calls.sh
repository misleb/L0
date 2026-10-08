#!/bin/sh
# tail_calls.sh EXE IR -- spec section 8's guarantee, where LLVM's optimizer
# does not supply it. At -O0 LLVM eliminates no call by itself, and a 1 MB
# stack holds about fifteen thousand frames, so a million iterations of each
# loop get through only if every tail call uses no stack. The -O2 build
# must agree.
set -eu
exe=$1
ir=$2
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/env.sh"
# The runtime text itself, not build/l0rt.o, whose bitcode would bring
# link-time optimization in with it.
"$CC" -O0 -Wno-override-module "$ir" "$ROOT/runtime/l0rt.ll" \
    "$ROOT/runtime/host-libc.ll" -o "$exe.O0"
want=$(printf '1000000\n1000000\n1000000\n500000\n500000500000')
for build in "$exe.O0" "$exe"; do
    if ! got=$(L0_STACK_MB=1 "$build" 1000000 2>&1); then
        echo "$build failed:"; echo "$got"
        exit 1
    fi
    if [ "$got" != "$want" ]; then
        echo "$build: expected"; echo "$want"; echo "got:"; echo "$got"
        exit 1
    fi
done
