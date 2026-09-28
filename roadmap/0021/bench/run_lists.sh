#!/bin/sh
# run_lists.sh SUFFIX [RUNS] -- measures the list and trie versions of the
# benchmarks, built as bench/bin/NAME.SUFFIX, and checks their outputs agree
# with each other and with the Python reference for paths.
set -eu
cd "$(dirname "$0")/.."
S=$1
N=${2:-5}
M="python3 bench/measure.py"
I=bench/inputs
B=bench/bin
O=bench/out
$M --in $I/text1m.txt --out $O/hist_list.$S.out --label hist_list.$S "$N" $B/hist_list.$S
$M --in $I/text1m.txt --out $O/hist_tree.$S.out --label hist_tree.$S "$N" $B/hist_tree.$S
cmp $O/hist_list.$S.out $O/hist_tree.$S.out && echo "  histograms agree"
$M --out $O/myers.$S.out --label myers.$S "$N" $B/myers.$S 10000
echo "  myers: $(cat $O/myers.$S.out)"
$M --in $I/graph0.txt --label paths0.$S 3 $B/paths.$S
$M --in $I/graph100.txt --out $O/paths.$S.out --label paths100.$S 3 $B/paths.$S
cmp $O/paths.$S.out $I/graph100.expected && echo "  paths agree with Python"
