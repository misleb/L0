#!/bin/sh
# Boots kernel.l0's image with one process, whose standard input is this
# script's, and exits with the kernel's status, which is the process's.
#
# Usage: tests/virt/user/run.sh KERNEL.elf IMAGE.elf WORK < input
#
#   KERNEL.elf  kernel.l0, built by tools/l0 build --target virt
#   IMAGE.elf   the process, built by tools/l0 build --target proc
#   WORK        a directory for the kernel's input
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

if [ $# -ne 3 ]; then
    echo "usage: run.sh KERNEL.elf IMAGE.elf WORK < input" >&2
    exit 2
fi
mkdir -p "$3"
"$HERE/bundle.sh" "$2" "$3" > "$3/bundle"
exec "$ROOT/tools/l0" boot "$1" < "$3/bundle"
