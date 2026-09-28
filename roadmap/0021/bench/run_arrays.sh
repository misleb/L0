#!/bin/sh
# run_arrays.sh SUFFIX [RUNS] -- measures the array benchmarks built as
# bench/bin/NAME.SUFFIX, checks their output against the list versions and
# Python, and reports array copies counted by the runtime (L0_ARRAY_STATS).
set -eu
cd "$(dirname "$0")/.."
S=$1
N=${2:-5}
M="python3 bench/measure.py"
I=bench/inputs
B=bench/bin
O=bench/out
stats() {
    echo "  counts: $(L0_ARRAY_STATS=1 "$@" 2>&1 >/dev/null | tr '\n' ' ')"
}
$M --in $I/text1m.txt --out $O/hist_array.$S.out --label hist_array.$S "$N" $B/hist_array.$S
cmp $O/hist_array.$S.out $O/hist_list.base.out && echo "  histogram agrees with the list version"
stats $B/hist_array.$S < $I/text1m.txt
$M --out $O/myers_array.$S.out --label myers_array.$S "$N" $B/myers_array.$S 10000
echo "  myers_array: $(cat $O/myers_array.$S.out) (list version: $(cat $O/myers.base.out))"
echo "  sums at D=2000: array $($B/myers_array.$S 2000 sum), list $($B/myers_list_sum.$S 2000)"
stats $B/myers_array.$S 10000
$M --in $I/graph0.txt --label paths_array0.$S 3 $B/paths_array.$S
stats $B/paths_array.$S < $I/graph0.txt
$M --in $I/graph100.txt --out $O/paths_array.$S.out --label paths_array100.$S 3 $B/paths_array.$S
cmp $O/paths_array.$S.out $I/graph100.expected && echo "  paths agree with Python"
stats $B/paths_array.$S < $I/graph100.txt
