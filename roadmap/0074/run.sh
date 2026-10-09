#!/bin/sh
# Usage: roadmap/0074/run.sh KERNEL.elf INPUT SLOT0.elf [SLOT1.elf [SLOT2.elf]]
# Boots kernel.ll on QEMU's virt board with each process image loaded by
# QEMU's loader at the physical address its ELF names, and INPUT, which may
# be empty, loaded at 0x50000000 as standard input, its length at
# 0x4FFFFFF8. A slot given as - is left empty. Standard output is the serial
# line; standard error and the exit status, slot 0's, come back by
# semihosting.
set -eu
kernel=$1
input=$2
shift 2
len=$(wc -c < "$input" | tr -d ' ')
dev="-device loader,addr=0x4FFFFFF8,data=$len,data-len=8"
if [ "$len" -gt 0 ]; then
    dev="$dev -device loader,file=$input,addr=0x50000000,force-raw=on"
fi
for p in "$@"; do
    if [ "$p" != - ]; then
        dev="$dev -device loader,file=$p"
    fi
done
# shellcheck disable=SC2086
exec qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2G -display none \
    -monitor none -serial stdio -semihosting $dev -kernel "$kernel" < /dev/null
