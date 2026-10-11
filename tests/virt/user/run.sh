#!/bin/sh
# Boots kernel.l0's image with its processes, whose standard input is this
# script's, and exits with the kernel's status, which is process 0's.
#
# Usage: tests/virt/user/run.sh KERNEL.elf WORK IMAGE.elf [IMAGE.elf ...] < input
#
#   KERNEL.elf  kernel.l0, built by tools/l0 build --target virt
#   WORK        a directory for the kernel's input
#   IMAGE.elf   a process, built by tools/l0 build --target proc; the
#               first is process 0
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

if [ $# -lt 3 ]; then
    echo "usage: run.sh KERNEL.elf WORK IMAGE.elf [IMAGE.elf ...] < input" >&2
    exit 2
fi
kernel=$1
work=$2
shift 2
mkdir -p "$work"
"$HERE/bundle.sh" "$work" "$@" > "$work/bundle"
exec "$ROOT/tools/l0" boot "$kernel" < "$work/bundle"
