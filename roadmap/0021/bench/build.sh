#!/bin/sh
# build.sh SUFFIX -- builds every benchmark with bench/bin/l0c-SUFFIX and
# bench/bin/l0rt-SUFFIX.o, as bench/bin/NAME.SUFFIX. With --lists-only, only
# the list and trie programs, which is all a compiler without arrays can do.
set -eu
cd "$(dirname "$0")/.."
S=$1
L0_COMPILER=$PWD/bench/bin/l0c-$S
L0_RUNTIME=$PWD/bench/bin/l0rt-$S.o
export L0_COMPILER L0_RUNTIME
R=roadmap/0014
B=bench/bin
tools/l0 build $R/text-tools/limits/01-no-array.l0 -o $B/hist_list.$S
tools/l0 build $R/text-tools/limits/01-no-array-tree.l0 -o $B/hist_tree.$S
tools/l0 build $R/bytes-encodings/limits/03-no-arrays.l0 -o $B/myers.$S
tools/l0 build bench/myers_list_sum.l0 -o $B/myers_list_sum.$S
tools/l0 build $R/data-structures/paths/paths.l0 $R/data-structures/paths/main.l0 -o $B/paths.$S
tools/l0 build $R/data-structures/limits/04-bytes-are-cons-cells.l0 -o $B/hold.$S
[ "${2:-}" = "--lists-only" ] && exit 0
tools/l0 build bench/hist_array.l0 -o $B/hist_array.$S
tools/l0 build bench/myers_array.l0 -o $B/myers_array.$S
tools/l0 build bench/paths_array.l0 bench/paths_array_main.l0 -o $B/paths_array.$S
echo "built *.$S"
