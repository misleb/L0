#!/bin/sh
# Writes the standard input kernel.l0 reads: the number of processes in
# decimal and a newline; for each, its image's length in decimal and a
# newline, and the image, the ELF tools/l0 build --target proc writes; and
# then the processes' own standard input,
# this script's. The layout is kernel.l0's own, not the toolchain's.
#
# Usage: tests/virt/user/bundle.sh IMAGE [IMAGE ...] < input > bundle
#
#   IMAGE  a process image, built by tools/l0 build --target proc; the
#          first is process 0, whose end ends the run
set -eu

if [ $# -lt 1 ]; then
    echo "usage: bundle.sh IMAGE [IMAGE ...] < input > bundle" >&2
    exit 2
fi
echo $#
for image in "$@"; do
    wc -c < "$image" | tr -d ' '
    cat "$image"
done
cat
