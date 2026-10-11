#!/bin/sh
# Writes the standard input kernel.l0 reads: the number of processes in
# decimal and a newline; for each, its image's length in decimal and a
# newline, and its raw bytes from 0xC0000000; and then the processes' own
# standard input, this script's.
#
# Usage: tests/virt/user/bundle.sh WORK IMAGE.elf [IMAGE.elf ...] < input > bundle
#
#   WORK       a directory for the images' raw bytes
#   IMAGE.elf  a process image, built by tools/l0 build --target proc;
#              the first is process 0, whose end ends the run
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
. "$ROOT/tools/env.sh"

if [ $# -lt 2 ]; then
    echo "usage: bundle.sh WORK IMAGE.elf [IMAGE.elf ...] < input > bundle" >&2
    exit 2
fi
work=$1
shift
objcopy="$LLVM_PREFIX/bin/llvm-objcopy"
[ -x "$objcopy" ] || objcopy=llvm-objcopy
mkdir -p "$work"
echo $#
i=0
for image in "$@"; do
    raw="$work/process$i.bin"
    "$objcopy" -O binary "$image" "$raw"
    wc -c < "$raw" | tr -d ' '
    cat "$raw"
    i=$((i + 1))
done
cat
