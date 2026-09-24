#!/bin/sh
# Apply each prototype option to the compiler's own IR (build/stage2.ll, the
# compiler built from current source), build it at -O0 and -O2, and check
# that the rewritten compiler still compiles compiler/*.l0 to exactly
# build/stage2.ll. Reports time, peak memory, and the smallest L0_STACK_MB
# (powers of two) with which it succeeds.
#
# Usage: experiments/tailcalls/compiler_test.sh [VARIANT ...]
#   (after tools/bootstrap.sh, from the repository root)
set -u
X=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$X/../.." && pwd)
CC=/opt/homebrew/opt/llvm/bin/clang
SRC=$ROOT/build/compiler-source.l0
REF=$ROOT/build/stage2.ll
cd "$X/out"
flags() {
    case $1 in
        base) echo "" ;;
        ret) echo --ret-direct ;;
        tail) echo --ret-direct --tail ;;
        mustsame) echo --ret-direct --musttail-same-arity ;;
        tailcc) echo --ret-direct --tailcc ;;
        loop) echo --ret-direct --selfloop ;;
    esac
}
same() {
    tail -n +2 "$1" | cmp -s - "$REF"
}
for v in ${*:-base ret tail mustsame tailcc loop}; do
    # shellcheck disable=SC2046
    python3 "$X/tailify.py" $(flags $v) < "$REF" > cc.$v.ll
    printf '%-9s musttail=%-5s tail=%-5s selfloops=%-4s\n' "$v" \
        "$(grep -c 'musttail call' cc.$v.ll)" \
        "$(grep -c '= tail call' cc.$v.ll)" \
        "$(grep -c 'br label %loop.head' cc.$v.ll)"
    for o in 0 2; do
        if ! $CC -O$o -Wno-override-module cc.$v.ll "$ROOT/build/l0rt.o" -o cc.$v.O$o 2> cc.$v.O$o.err; then
            echo "  -O$o: does not build: $(grep -m1 error cc.$v.O$o.err)"
            continue
        fi
        t=$( { /usr/bin/time -l ./cc.$v.O$o < "$SRC" > cc.$v.O$o.out; } 2>&1 )
        secs=$(echo "$t" | awk '/real/ {print $1}')
        rss=$(echo "$t" | awk '/maximum resident/ {printf "%d MB", $1/1048576}')
        if same cc.$v.O$o.out; then ok="output identical to stage2.ll"; else ok="OUTPUT DIFFERS"; fi
        minmb=none
        for mb in 1 2 4 8 16 32 64 128 256 512; do
            if L0_STACK_MB=$mb ./cc.$v.O$o < "$SRC" > cc.tmp.out 2>/dev/null && same cc.tmp.out; then
                minmb=$mb; break
            fi
        done
        echo "  -O$o: ${secs}s, peak RSS $rss, $ok, smallest working L0_STACK_MB: $minmb"
    done
done
rm -f cc.tmp.out
