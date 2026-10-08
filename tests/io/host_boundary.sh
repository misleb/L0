#!/bin/sh
# host_boundary.sh EXE IR -- spec section 10.3's boundary between the
# runtime and its host file. runtime/l0rt.ll declares nothing but the
# l0_host_ functions, LLVM intrinsics, memcmp, and what compiled code
# defines; and runtime/host-libc.ll defines every l0_host_ function
# l0rt.ll declares, and l0rt.ll defines the l0_rt_run it calls. A libc call
# slipping back into l0rt.ll would work on macOS and Linux and break a host
# without an operating system, so only this catches it.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
rt="$ROOT/runtime/l0rt.ll"
host="$ROOT/runtime/host-libc.ll"

stray=$(grep '^declare' "$rt" |
    grep -v -e '@l0_host_' -e '@llvm\.' -e '@memcmp(' -e '@l0_f_main(' || true)
if [ -n "$stray" ]; then
    echo "runtime/l0rt.ll declares what is not the host interface:"
    echo "$stray"
    exit 1
fi

for f in $(grep '^declare' "$rt" | sed -n 's/.*@\(l0_host_[a-z_]*\)(.*/\1/p'); do
    if ! grep -q "^define .*@$f(" "$host"; then
        echo "runtime/host-libc.ll does not define $f"
        exit 1
    fi
done

if ! grep -q '^define i64 @l0_rt_run(' "$rt"; then
    echo "runtime/l0rt.ll does not define l0_rt_run"
    exit 1
fi
