#!/bin/sh
# Run depth.sh over every prototype build that build_protos.sh produced.
#
# Usage: experiments/tailcalls/proto_matrix.sh [VARIANT ...]
set -u
X=$(cd "$(dirname "$0")" && pwd)
cd "$X/out"
variants=${*:-"ret tail mustsame tailcc loop loopnh"}
for c in self mutual mutual_wide listloop walk matchloop nontail; do
    max=1000000000
    [ "$c" = walk ] && max=30000000
    for v in $variants; do
        for b in $v.O0 $v.O2 $v.noinl.O2; do
            [ -x "./$c.$b" ] || { printf '%-12s %-18s %s\n' "$c" "$b" "(does not build)"; continue; }
            printf '%-12s %-18s %s\n' "$c" "$b" "$("$X/depth.sh" "./$c.$b" "$max")"
        done
    done
done
