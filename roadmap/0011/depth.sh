#!/bin/sh
# Find the deepest n a case survives. Each case takes n as its first argument
# and makes n L0 calls in a chain; a run fails with "stack exhausted" (exit 70)
# when the stack runs out.
#
# Usage: experiments/tailcalls/depth.sh BINARY [MAX]
#   Tries n = 10^3, 10^4, ... up to MAX (default 10^9). If every n passes it
#   prints "no limit up to MAX". Otherwise it bisects between the last pass and
#   the first failure to within 1% and prints "limit ~N (first failure: ...)".
#   L0_STACK_MB in the environment is passed through to the program.
set -u
bin=$1
max=${2:-1000000000}

run() {
    out=$("$bin" "$1" 2>&1 >/dev/null)
    rc=$?
    if [ $rc -eq 0 ]; then echo ok; else echo "fail rc=$rc: $out"; fi
}

lo=0
n=1000
while [ "$n" -le "$max" ]; do
    r=$(run "$n")
    case $r in
        ok) lo=$n; n=$((n * 10)) ;;
        *) hi=$n; why=$r; break ;;
    esac
done
if [ "$n" -gt "$max" ]; then
    echo "no limit up to $max"
    exit 0
fi
while [ $((hi - lo)) -gt $((lo / 100 + 1)) ]; do
    mid=$(((lo + hi) / 2))
    r=$(run "$mid")
    case $r in
        ok) lo=$mid ;;
        *) hi=$mid; why=$r ;;
    esac
done
echo "limit ~$lo ($why)"
