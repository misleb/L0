#!/bin/sh
# 0074's prototype, built from the repository root:
#
#   roadmap/0074/build.sh kernel OUT.elf
#       kernel.ll, linked by kernel.ld
#   roadmap/0074/build.sh proc PROG SLOT OUT.elf
#       an L0 program, PROG.l0 compiled by tools/l0 emit or PROG.ll the
#       compiler already wrote, with runtime/l0rt.ll unchanged and proc.ll
#       as its host file, linked by proc.ld at 0xC0000000 and loaded at
#       slot SLOT's physical address
#   roadmap/0074/build.sh raw FILE.ll SLOT OUT.elf
#       a process that is not an L0 program, such as fault.ll
#
# clang on the host compiles; ld.lld runs in the l0-virt-link container
# (tools/virt/Dockerfile), since the host's is blocked. OUT goes under tmp/.
set -eu
LLVM=${LLVM_PREFIX:-/opt/homebrew/opt/llvm}/bin
here=roadmap/0074
cc="$LLVM/clang --target=aarch64-none-elf -O2 -Wno-override-module"

link() {
    docker run --rm -v "$PWD:/w" -w /w l0-virt-link ld.lld "$@"
}

load_addr() {
    case $1 in
        0) echo 0x58000000 ;;
        1) echo 0x58400000 ;;
        2) echo 0x58800000 ;;
        *) echo "slot must be 0, 1, or 2" >&2; exit 2 ;;
    esac
}

case $1 in
    kernel)
        out=$2
        $cc -c "$here/kernel.ll" -o "${out%.elf}.o"
        link -T "$here/kernel.ld" "${out%.elf}.o" -o "$out"
        ;;
    proc)
        prog=$2
        at=$(load_addr "$3")
        out=$4
        base=${out%.elf}
        case $prog in
            *.l0) tools/l0 emit "$prog" > "$base.ll" ;;
            *) cp "$prog" "$base.ll" ;;
        esac
        $cc -c -emit-llvm "$here/proc.ll" -o "$base.host.bc"
        $cc -c -emit-llvm runtime/l0rt.ll -o "$base.rt.bc"
        $cc -c "$base.ll" \
            -Xclang -mlink-bitcode-file -Xclang "$base.rt.bc" \
            -Xclang -mlink-bitcode-file -Xclang "$base.host.bc" -o "$base.o"
        link -T "$here/proc.ld" --defsym=__load="$at" "$base.o" -o "$out"
        ;;
    raw)
        at=$(load_addr "$3")
        out=$4
        $cc -c "$2" -o "${out%.elf}.o"
        link -T "$here/proc.ld" --defsym=__load="$at" "${out%.elf}.o" -o "$out"
        ;;
    *)
        echo "usage: build.sh kernel OUT | proc PROG SLOT OUT | raw FILE.ll SLOT OUT" >&2
        exit 2
        ;;
esac
