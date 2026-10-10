#!/bin/sh
# Writes the standard input kernel.l0 reads: a process image's length in
# decimal and a newline, its raw bytes from 0xC0000000, and then the
# process's own standard input, this script's.
#
# Usage: tests/virt/user/bundle.sh IMAGE.elf WORK < input > bundle
#
#   IMAGE.elf  a process image, built by tools/l0 build --target proc
#   WORK       a directory for the image's raw bytes
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
. "$ROOT/tools/env.sh"

if [ $# -ne 2 ]; then
    echo "usage: bundle.sh IMAGE.elf WORK < input > bundle" >&2
    exit 2
fi
objcopy="$LLVM_PREFIX/bin/llvm-objcopy"
[ -x "$objcopy" ] || objcopy=llvm-objcopy
mkdir -p "$2"
raw="$2/$(basename "$1" .elf).bin"
"$objcopy" -O binary "$1" "$raw"
wc -c < "$raw" | tr -d ' '
cat "$raw"
cat
