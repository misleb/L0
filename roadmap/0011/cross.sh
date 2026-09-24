#!/bin/sh
# Cross-compile the mutual and mutual_wide prototypes to assembly for other
# targets and count, per variant and level, the calls between the recursive
# functions that are real calls versus jumps. Nothing is linked or run.
#
# Usage: experiments/tailcalls/cross.sh   (after build_protos.sh)
set -u
X=$(cd "$(dirname "$0")" && pwd)
CC=/opt/homebrew/opt/llvm/bin/clang
cd "$X/out"
for tgt in x86_64-apple-macos x86_64-linux-gnu aarch64-linux-gnu riscv64-linux-gnu armv7-linux-gnueabihf wasm32-wasi; do
    for c in mutual mutual_wide; do
        for v in "" .tail .tailcc; do
            for o in 0 2; do
                in=$c$v.noinl.ll
                [ -z "$v" ] && in=$c.noinl.ll
                s=$($CC -target $tgt -O$o -S -Wno-override-module "$in" -o - 2>&1)
                if [ $? -ne 0 ]; then
                    printf '%-20s %-18s -O%s  error: %s\n' $tgt "$c${v:-.base}" $o "$(echo "$s" | grep -m1 error)"
                    continue
                fi
                # A call names its target after call/bl/jal; a jump after
                # jmp/b/j/tail. Only calls between ping/pong/wide count.
                calls=$(echo "$s" | grep -Ec '^[[:space:]]+(call|callq|bl|jal|return_call)[[:space:]]+_?l0_f_(ping|pong|wide)(@PLT)?([[:space:]]|$)')
                jumps=$(echo "$s" | grep -Ec '^[[:space:]]+(jmp|jmpq|b|j|tail|return_call)[[:space:]]+_?l0_f_(ping|pong|wide)(@PLT)?([[:space:]]|$)')
                printf '%-20s %-18s -O%s  calls=%s jumps=%s\n' $tgt "$c${v:-.base}" $o "$calls" "$jumps"
            done
        done
    done
done
