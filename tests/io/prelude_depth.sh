#!/bin/sh
# prelude_depth.sh EXE IR -- the prelude's length and append use no stack per
# element. Built at -O0, where LLVM turns no recursion into a loop by itself,
# and run on a 1 MB stack over a million elements.
set -eu
exe=$1
ir=$2
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/env.sh"
# The runtime text itself, not build/l0rt.o, whose bitcode would bring
# link-time optimization in with it.
"$CC" -O0 -Wno-override-module "$ir" "$ROOT/runtime/l0rt.ll" -o "$exe.O0"
want=$(printf '1000000\n1000001\n1000000')
if ! got=$(L0_STACK_MB=1 "$exe.O0" 1000000 2>&1); then
    echo "failed:"; echo "$got"
    exit 1
fi
if [ "$got" != "$want" ]; then
    echo "expected"; echo "$want"; echo "got:"; echo "$got"
    exit 1
fi
