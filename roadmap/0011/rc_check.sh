#!/bin/sh
# Run every case and prototype build under L0_RC_CHECK, which makes the
# runtime poison freed blocks (so a use after free is a runtime error) and
# report any counted block still live at exit. Each run must exit 0, write
# nothing to stderr, and print what the unmodified -O2 build prints.
#
# Usage: experiments/tailcalls/rc_check.sh   (after build_protos.sh)
set -u
X=$(cd "$(dirname "$0")" && pwd)
cd "$X/out"
n=20000
bad=0
total=0
for c in self mutual mutual_wide listloop walk matchloop nontail nested; do
    want=$(./$c.brew.O2 $n 2>/dev/null || ./$c.base.O2 $n)
    for b in ./$c.*O0 ./$c.*O2; do
        [ -x "$b" ] || continue
        total=$((total + 1))
        got=$(L0_RC_CHECK=1 "$b" $n 2> rc.err)
        rc=$?
        if [ $rc -ne 0 ] || [ -s rc.err ] || [ "$got" != "$want" ]; then
            echo "FAIL $b rc=$rc out=$got want=$want err=$(head -c 200 rc.err)"
            bad=$((bad + 1))
        fi
    done
done
rm -f rc.err
echo "$total builds checked under L0_RC_CHECK, $bad failures"
