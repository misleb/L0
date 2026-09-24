#!/bin/sh
# Build every prototype option (tailify.py) for every case at -O0 and -O2,
# and at -O2 with every function noinline. Run after build_cases.sh.
#
# Variants:
#   ret      --ret-direct                 option 4 alone
#   tail     --ret-direct --tail          option 4 + explicit tail marker
#   mustccc  --ret-direct --musttail      option 1, C convention
#   mustsame --ret-direct --musttail-same-arity   option 1, C convention,
#            musttail only where the arities match
#   tailcc   --ret-direct --tailcc        option 1, tailcc + musttail
#   loop     --ret-direct --selfloop      option 3, allocas hoisted
#   loopnh   --ret-direct --selfloop --no-hoist   option 3, allocas left in place
set -u
X=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$X/../.." && pwd)
CC=/opt/homebrew/opt/llvm/bin/clang
cd "$X/out"
flags() {
    case $1 in
        ret) echo --ret-direct ;;
        tail) echo --ret-direct --tail ;;
        mustccc) echo --ret-direct --musttail ;;
        mustsame) echo --ret-direct --musttail-same-arity ;;
        tailcc) echo --ret-direct --tailcc ;;
        loop) echo --ret-direct --selfloop ;;
        loopnh) echo --ret-direct --selfloop --no-hoist ;;
    esac
}
for c in self mutual mutual_wide listloop walk matchloop nontail; do
    for v in ${VARIANTS:-ret tail mustccc mustsame tailcc loop loopnh}; do
        # shellcheck disable=SC2046
        python3 "$X/tailify.py" $(flags $v) < $c.ll > $c.$v.ll
        # shellcheck disable=SC2046
        python3 "$X/tailify.py" $(flags $v) --noinline < $c.ll > $c.$v.noinl.ll
        for o in 0 2; do
            if ! $CC -O$o -Wno-override-module $c.$v.ll "$ROOT/build/l0rt.o" -o $c.$v.O$o 2> $c.$v.O$o.err; then
                echo "$c $v -O$o: does not compile: $(grep -m1 error $c.$v.O$o.err)"
                rm -f $c.$v.O$o
            fi
        done
        $CC -O0 -S -Wno-override-module $c.$v.ll -o $c.$v.O0.s 2>/dev/null
        if ! $CC -O2 -Wno-override-module $c.$v.noinl.ll "$ROOT/build/l0rt.o" -o $c.$v.noinl.O2 2>/dev/null; then
            rm -f $c.$v.noinl.O2
        fi
        $CC -O2 -S -Wno-override-module $c.$v.noinl.ll -o $c.$v.noinl.O2.s 2>/dev/null
    done
done
echo done
