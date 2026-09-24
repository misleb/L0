#!/bin/sh
# Runs every test in the given files under L0_RC_CHECK and prints any test
# whose standard error mentions a leak or a use after free.
#
#   programs/rc_check_tests.sh programs/json/json.l0 programs/json/json_test.l0
#
# l0 test shows a test's standard error only when the test fails, and the
# runtime's leak report does not change the exit status, so a leak in a
# passing test is invisible there. This builds the same kind of main l0 test
# generates and looks at standard error itself. Run from the repository root.

set -eu
tmp=$(mktemp -d "${TMPDIR:-/tmp}/rccheck.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

tests=$(cat "$@" |
    sed -n 's/^(def[[:space:]]\{1,\}\(test_[A-Za-z0-9_]*\)[[:space:]]*().*/\1/p')
{
    echo "(def main () int"
    echo "  (let name (arg 0)"
    closes=""
    for t in $tests; do
        echo "  (if (list_eq name \"$t\") (test_status ($t))"
        closes="$closes)"
    done
    echo "  2$closes))"
} > "$tmp/main.l0"

tools/l0 build lib/test.l0 "$@" "$tmp/main.l0" -o "$tmp/prog"
bad=0
for t in $tests; do
    L0_RC_CHECK=1 "$tmp/prog" "$t" > /dev/null 2> "$tmp/err" || true
    if grep -q '^l0: ' "$tmp/err"; then
        echo "$t: $(grep '^l0: ' "$tmp/err")"
        bad=1
    fi
done
if [ "$bad" = 0 ]; then
    echo "rc check: $(echo $tests | wc -w | tr -d ' ') tests, no runtime reports"
fi
