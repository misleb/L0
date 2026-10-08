#!/bin/sh
# Usage: roadmap/0068/build.sh PROG.ll OUT.elf, from the repository root.
# Links a compiled program's IR with runtime/l0rt.ll, unchanged, and
# metal.ll, optimizes them together on the host, and links the object into
# an image for QEMU's virt board in the l0-link-proto container, built from
# the Dockerfile here, since the host's ld.lld is blocked. Both paths are
# relative to the repository root, which the container mounts; put OUT
# under tmp/.
set -eu
LLVM=${LLVM_PREFIX:-/opt/homebrew/opt/llvm}/bin
here=roadmap/0068
prog=$1
out=$2
base=${out%.elf}
"$LLVM/llvm-link" "$prog" runtime/l0rt.ll "$here/metal.ll" -o "$base.bc"
"$LLVM/opt" "-passes=internalize,default<O2>" \
    -internalize-public-api-list=_start,metal_main,metal_fault,metal_pt,memcpy,memmove,memset,memcmp,bcmp \
    "$base.bc" -o "$base.opt.bc"
"$LLVM/clang" --target=aarch64-none-elf -O2 -Wno-override-module -c "$base.opt.bc" -o "$base.o"
docker run --rm --platform linux/arm64 -v "$PWD:/w" -w /w l0-link-proto:arm64 \
    ld.lld -T "$here/metal.ld" "$base.o" -o "$out"
