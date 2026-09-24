#!/bin/sh
# Run depth.sh over every case and build variant that build_cases.sh (and the
# noinline variants) produced, with the default 512 MB stack.
#
# Usage: experiments/tailcalls/matrix.sh [VARIANT ...]
set -u
X=$(cd "$(dirname "$0")" && pwd)
cd "$X/out"
variants=${*:-"brew.O0 brew.O1 brew.O2 noinl.brew.O2 apple.O0 apple.O2 noinl.apple.O2"}
for c in self mutual mutual_wide listloop walk matchloop nontail; do
    max=1000000000
    [ "$c" = walk ] && max=30000000   # walk holds n cells at once: 32 bytes each
    for v in $variants; do
        b=./$c.$v
        [ -x "$b" ] || continue
        printf '%-12s %-16s %s\n' "$c" "$v" "$("$X/depth.sh" "$b" "$max")"
    done
done
