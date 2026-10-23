#!/bin/sh
# Boots a CPU's kernel.ll on QEMU's virt board with up to three processes,
# and exits with the first one's status, or 99 if the kernel killed it.
#
# Usage: tests/virt/proc/harness/boot.sh WORK ARGS SLOT0 [SLOT1 [SLOT2]] < INPUT
#        tests/virt/proc/harness/boot.sh WORK
#
#   WORK    a directory for the kernel's image and what QEMU loads for it,
#           inside the repository, where the linker container can see it
#   ARGS    a file of slot 0's arguments, one per line, or - for none
#   SLOTn   a process image, built by tools/l0 build --target proc, its
#           file at most 4 MB; fault, for fault.ll beside the kernel; or -
#           for an empty slot
#
# The CPU is L0_ARCH's, aarch64 unless it names another, and its kernel,
# fault.ll, and board.sh, which says where the kernel reads what is loaded
# for it and how QEMU boots it, are in the directory named for it here.
# Standard input is the processes' standard input. Standard output is the
# board's serial line; standard error and the exit status come back by
# semihosting. The kernel and fault.ll are linked once into WORK, by
# L0_VIRT_LD if it names an ld.lld, or else in the l0-virt-link container,
# as tools/l0 links --target virt: the kernel as an ELF, with elf.ll, its
# loader for processes, beside it, which QEMU boots as it is, needing no
# boot arguments, and fault.ll as a process is, an ELF. Given WORK alone,
# it links them and boots nothing, so that boots side by side, as
# tools/test.sh --virt runs them, find them linked; each boot's own input
# is in WORK under its process's number, and gone once QEMU is.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
. "$ROOT/tools/env.sh"

if [ $# -ne 1 ] && [ $# -lt 3 ]; then
    echo "usage: boot.sh WORK ARGS SLOT0 [SLOT1 [SLOT2]] < input" >&2
    echo "       boot.sh WORK" >&2
    exit 2
fi
work=$1
shift
link_only=1
args=""
if [ $# -gt 0 ]; then
    link_only=0
    args=$1
    shift
fi
if [ $# -gt 3 ]; then
    echo "boot.sh: the kernel has three slots" >&2
    exit 2
fi
arch=${L0_ARCH:-aarch64}
H="$HERE/$arch"
if [ ! -f "$H/kernel.ll" ]; then
    echo "boot.sh: no harness kernel for $arch" >&2
    exit 2
fi
. "$H/board.sh"
T_CFLAGS="" T_LDFLAGS=""
. "$ROOT/runtime/targets/proc-$arch.target"
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

# image LL LD OUT [ARG ...] links LL by LD into OUT, with each ARG, a flag
# or an object, unless OUT is newer than LL, LD, and the loader's object.
image() {
    ll=$1
    ld=$2
    out=$3
    shift 3
    if [ ! -f "$out" ] || [ "$ll" -nt "$out" ] || [ "$ld" -nt "$out" ] ||
        [ "$work/elf.o" -nt "$out" ]; then
        # shellcheck disable=SC2086
        "$CC" --target="$T_TRIPLE" $T_CFLAGS -O2 -c "$ll" -o "$out.o"
        lld -T "$ld" "$@" "$out.o" -o "$out"
    fi
}
if [ ! -f "$work/elf.o" ] || [ "$HERE/elf.ll" -nt "$work/elf.o" ]; then
    # shellcheck disable=SC2086
    "$CC" --target="$T_TRIPLE" $T_CFLAGS -O2 -Wno-override-module -c "$HERE/elf.ll" \
        -o "$work/elf.o"
fi
image "$H/kernel.ll" "$H/kernel.ld" "$work/kernel.elf" "$work/elf.o"
# shellcheck disable=SC2086
image "$H/fault.ll" "$ROOT/runtime/proc.ld" "$work/fault.img" $T_LDFLAGS
[ "$link_only" = 0 ] || exit 0

stdin="$work/stdin.$$"
argv="$work/args.$$"
trap 'rm -f "$stdin" "$argv"' EXIT
cat > "$stdin"
len=$(wc -c < "$stdin" | tr -d ' ')
if [ "$len" -gt 134217720 ]; then
    echo "boot.sh: the kernel takes at most 128 MB of standard input" >&2
    exit 2
fi
dev="-device loader,addr=$H_INPUT_LEN_AT,data=$len,data-len=8"
if [ "$len" -gt 0 ]; then
    dev="$dev -device loader,file=$stdin,addr=$H_INPUT_AT,force-raw=on"
fi

# Slot 0's arguments, each line ending in a NUL rather than a newline.
alen=0
if [ "$args" != - ]; then
    tr '\n' '\000' < "$args" > "$argv"
    alen=$(wc -c < "$argv" | tr -d ' ')
fi
dev="$dev -device loader,addr=$H_ARGS_LEN_AT,data=$alen,data-len=8"
if [ "$alen" -gt 0 ]; then
    dev="$dev -device loader,file=$argv,addr=$H_ARGS_AT,force-raw=on"
fi

# Each process's image, its file as it is, at its slot's physical address,
# 4 MB apart, where the kernel puts its segments in place.
slot=0
for p in "$@"; do
    case $p in
        -) ;;
        fault) img="$work/fault.img" ;;
        *) img=$p ;;
    esac
    if [ "$p" != - ]; then
        if [ "$(wc -c < "$img" | tr -d ' ')" -gt 4194304 ]; then
            echo "boot.sh: $img is over a slot's 4 MB" >&2
            exit 2
        fi
        addr=$(printf '0x%X' $((H_SLOT_BASE + slot * 0x400000)))
        dev="$dev -device loader,file=$img,addr=$addr,force-raw=on"
    fi
    slot=$((slot + 1))
done

# Where firmware writes on QEMU's standard output, the serial line is a
# descriptor of its own, 3, which is ours, and QEMU's goes nowhere. QEMU's
# status, the first process's, is this script's, once the input it was
# given is removed.
status=0
if [ "$H_SERIAL" = fd3 ]; then
    # shellcheck disable=SC2086
    "$H_QEMU" $H_QEMU_ARGS -display none -monitor none \
        -chardev file,id=l0serial,path=/dev/fd/3,append=on -serial chardev:l0serial \
        $dev -kernel "$work/kernel.elf" 3>&1 > /dev/null < /dev/null || status=$?
else
    # shellcheck disable=SC2086
    "$H_QEMU" $H_QEMU_ARGS -display none -monitor none -serial stdio \
        $dev -kernel "$work/kernel.elf" < /dev/null || status=$?
fi
exit "$status"
