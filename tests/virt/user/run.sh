#!/bin/sh
# Boots kernel.l0's image with its processes, whose standard input is this
# script's, and exits with the kernel's status, which is process 0's.
#
# Usage: tests/virt/user/run.sh KERNEL WORK ARGS IMAGE [IMAGE ...] < input
#
#   KERNEL      kernel.l0, built by tools/l0 build --target virt
#   WORK        a directory for the kernel's input, each run's under its
#               process's number, and gone once the board is, so that runs
#               can share it
#   ARGS        a file of the kernel's boot arguments, one per line, or -
#               for none: "N:VALUE" gives process N the argument VALUE
#   IMAGE       a process, built by tools/l0 build --target proc; the
#               first is process 0
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

if [ $# -lt 4 ]; then
    echo "usage: run.sh KERNEL WORK ARGS IMAGE [IMAGE ...] < input" >&2
    exit 2
fi
kernel=$1
work=$2
args=$3
shift 3
mkdir -p "$work"
bundle="$work/bundle.$$"
trap 'rm -f "$bundle"' EXIT
"$HERE/bundle.sh" "$@" > "$bundle"
kargs=""
[ "$args" = - ] || kargs=$(cat "$args")
status=0
# shellcheck disable=SC2086
"$ROOT/tools/l0" boot "$kernel" $kargs < "$bundle" || status=$?
exit "$status"
