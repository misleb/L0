#!/bin/sh
# Boots kernel.l0's image with its processes, whose standard input is this
# script's, and exits with the kernel's status, which is process 0's.
#
# Usage: tests/virt/user/run.sh KERNEL WORK ARGS IMAGE.elf [IMAGE.elf ...] < input
#
#   KERNEL      kernel.l0, built by tools/l0 build --target virt
#   WORK        a directory for the kernel's input
#   ARGS        a file of the kernel's boot arguments, one per line, or -
#               for none: "N:VALUE" gives process N the argument VALUE
#   IMAGE.elf   a process, built by tools/l0 build --target proc; the
#               first is process 0
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

if [ $# -lt 4 ]; then
    echo "usage: run.sh KERNEL WORK ARGS IMAGE.elf [IMAGE.elf ...] < input" >&2
    exit 2
fi
kernel=$1
work=$2
args=$3
shift 3
mkdir -p "$work"
"$HERE/bundle.sh" "$work" "$@" > "$work/bundle"
if [ "$args" = - ]; then
    exec "$ROOT/tools/l0" boot "$kernel" < "$work/bundle"
fi
# shellcheck disable=SC2046
exec "$ROOT/tools/l0" boot "$kernel" $(cat "$args") < "$work/bundle"
