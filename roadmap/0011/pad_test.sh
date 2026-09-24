#!/bin/sh
# Uniform-arity musttail under the C convention: every internal function
# padded to the module's largest arity (pad), or to the largest arity in its
# connected component of the tail-call graph (padc). Depth at -O0 and -O2 on
# the cases, then the compiler: identical self-compilation output, smallest
# working stack, text size. Then the padded mutual_wide cross-compiled for
# targets whose backends reject tailcc.
#
# Usage: experiments/tailcalls/pad_test.sh   (after build_cases.sh)
set -u
X=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$X/../.." && pwd)
CC=/opt/homebrew/opt/llvm/bin/clang
SRC=$ROOT/build/compiler-source.l0
REF=$ROOT/build/stage2.ll
cd "$X/out"
flags() {
    case $1 in
        pad) echo --ret-direct --musttail --pad-arity ;;
        padc) echo --ret-direct --pad-component ;;
    esac
}
for v in pad padc; do
    for c in self mutual mutual_wide listloop walk matchloop nested; do
        # shellcheck disable=SC2046
        python3 "$X/tailify.py" $(flags $v) < $c.ll > $c.$v.ll 2>/dev/null
        for o in 0 2; do
            $CC -O$o -Wno-override-module $c.$v.ll "$ROOT/build/l0rt.o" -o $c.$v.O$o
            rc=$(L0_RC_CHECK=1 ./$c.$v.O$o 20000 2>&1 >/dev/null | head -c 100)
            printf '%-5s %-12s -O%s  %s  rc-check stderr: "%s"\n' $v $c $o \
                "$("$X/depth.sh" ./$c.$v.O$o 100000000)" "$rc"
        done
    done
    # shellcheck disable=SC2046
    python3 "$X/tailify.py" $(flags $v) < "$REF" > cc.$v.ll
    for o in 0 2; do
        $CC -O$o -Wno-override-module cc.$v.ll "$ROOT/build/l0rt.o" -o cc.$v.O$o
        if ./cc.$v.O$o < "$SRC" | tail -n +2 | cmp -s - "$REF"; then same=identical; else same=DIFFERS; fi
        mb=none
        for m in 1 2 4 8 16 32 64 128; do
            if L0_STACK_MB=$m ./cc.$v.O$o < "$SRC" > /dev/null 2>&1; then mb=$m; break; fi
        done
        printf '%-5s compiler     -O%s  output %s, smallest L0_STACK_MB %s, __text %s bytes\n' \
            $v $o $same $mb "$(size -m cc.$v.O$o | awk '/Section __text/ {print $3; exit}')"
    done
done
for tgt in riscv64-linux-gnu armv7-linux-gnueabihf x86_64-linux-gnu wasm32-wasi; do
    python3 "$X/tailify.py" --ret-direct --musttail --pad-arity --noinline < mutual_wide.ll > mutual_wide.pad.noinl.ll
    for o in 0 2; do
        s=$($CC -target $tgt -O$o -S -Wno-override-module mutual_wide.pad.noinl.ll -o - 2>&1)
        if [ $? -ne 0 ]; then
            echo "pad mutual_wide $tgt -O$o: $(echo "$s" | grep -m1 -i error | cut -c1-140)"
        else
            echo "pad mutual_wide $tgt -O$o: calls=$(echo "$s" | grep -Ec '^[[:space:]]+(call|callq|bl|jal)[[:space:]]+_?l0_f_(pong|wide)') jumps=$(echo "$s" | grep -Ec '^[[:space:]]+(jmp|b|j|tail)[[:space:]]+_?l0_f_(pong|wide)')"
        fi
    done
done
