#!/bin/sh
# Usage: roadmap/0068/run.sh IMAGE.elf [INPUT]
# Boots the image on QEMU's virt board. INPUT, if given, is loaded at
# 0x50000000 as standard input, with its length at 0x4FFFFFF8. Standard
# output is the serial line, standard error and the exit status come back
# by semihosting.
set -eu
img=$1
dev=
if [ $# -ge 2 ]; then
    len=$(wc -c < "$2" | tr -d ' ')
    dev="-device loader,addr=0x4FFFFFF8,data=$len,data-len=8 -device loader,file=$2,addr=0x50000000,force-raw=on"
fi
# shellcheck disable=SC2086
exec qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2G -display none \
    -monitor none -serial stdio -semihosting $dev -kernel "$img"
