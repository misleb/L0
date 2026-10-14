#!/bin/sh
# Boots kernel.ll on QEMU's virt board with up to three processes, and
# exits with the first one's status, or 99 if the kernel killed it.
#
# Usage: tests/virt/proc/harness/boot.sh WORK ARGS SLOT0 [SLOT1 [SLOT2]] < INPUT
#
#   WORK    a directory for the kernel's image and the processes' raw bytes,
#           inside the repository, where the linker container can see it
#   ARGS    a file of slot 0's arguments, one per line, or - for none
#   SLOTn   a process image, built by tools/l0 build --target proc, raw;
#           fault, for fault.ll beside it; or - for an empty slot
#
# Standard input is the processes' standard input. Standard output is the
# board's serial line; standard error and the exit status come back by
# semihosting. The kernel and fault.ll are linked once into WORK, by
# L0_VIRT_LD if it names an ld.lld, or else in the l0-virt-link container,
# as tools/l0 links --target virt: the kernel as an ELF, which QEMU boots
# as it is, needing no boot arguments, and fault.ll raw, as a process.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
. "$ROOT/tools/env.sh"

if [ $# -lt 3 ]; then
    echo "usage: boot.sh WORK ARGS SLOT0 [SLOT1 [SLOT2]] < input" >&2
    exit 2
fi
work=$1
args=$2
shift 2
if [ $# -gt 3 ]; then
    echo "boot.sh: the kernel has three slots" >&2
    exit 2
fi
mkdir -p "$work"
work=$(cd "$work" && pwd)

lld() {
    if [ -n "${L0_VIRT_LD:-}" ]; then
        "$L0_VIRT_LD" "$@"
    else
        if ! docker image inspect l0-virt-link > /dev/null 2>&1; then
            docker build -q -t l0-virt-link "$ROOT/tools/virt" > /dev/null
        fi
        docker run --rm -v "$ROOT:$ROOT" -w "$ROOT" l0-virt-link ld.lld "$@"
    fi
}

# image LL LD OUT [FLAG ...] links LL by LD into OUT, unless OUT is newer
# than both.
image() {
    ll=$1
    ld=$2
    out=$3
    shift 3
    if [ ! -f "$out" ] || [ "$ll" -nt "$out" ] || [ "$ld" -nt "$out" ]; then
        "$CC" --target=aarch64-none-elf -O2 -c "$ll" -o "$out.o"
        lld -T "$ld" "$@" "$out.o" -o "$out"
    fi
}
image "$HERE/kernel.ll" "$HERE/kernel.ld" "$work/kernel.elf"
image "$HERE/fault.ll" "$ROOT/runtime/proc.ld" "$work/fault.img" --oformat binary

cat > "$work/stdin"
len=$(wc -c < "$work/stdin" | tr -d ' ')
if [ "$len" -gt 134217720 ]; then
    echo "boot.sh: the kernel takes at most 128 MB of standard input" >&2
    exit 2
fi
dev="-device loader,addr=0x4FFFFFF8,data=$len,data-len=8"
if [ "$len" -gt 0 ]; then
    dev="$dev -device loader,file=$work/stdin,addr=0x50000000,force-raw=on"
fi

# Slot 0's arguments, each line ending in a NUL rather than a newline.
alen=0
if [ "$args" != - ]; then
    tr '\n' '\000' < "$args" > "$work/args"
    alen=$(wc -c < "$work/args" | tr -d ' ')
fi
dev="$dev -device loader,addr=0x5EFFFFF8,data=$alen,data-len=8"
if [ "$alen" -gt 0 ]; then
    dev="$dev -device loader,file=$work/args,addr=0x5F000000,force-raw=on"
fi

# Each process's image, its raw bytes from 0xC0000000, at its slot's
# physical address; its bss is RAM that QEMU starts zero.
slot=0
for p in "$@"; do
    case $p in
        -) ;;
        fault) img="$work/fault.img" ;;
        *) img=$p ;;
    esac
    if [ "$p" != - ]; then
        addr=$(printf '0x%X' $((0x58000000 + slot * 0x400000)))
        dev="$dev -device loader,file=$img,addr=$addr,force-raw=on"
    fi
    slot=$((slot + 1))
done

# shellcheck disable=SC2086
exec qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2G -display none \
    -monitor none -serial stdio -semihosting $dev \
    -kernel "$work/kernel.elf" < /dev/null
