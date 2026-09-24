#!/bin/sh
# framework.sh EXE -- tests l0 test itself, on the fixture in
# tests/io/framework/, against hand-written expectations. EXE is unused.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
fixture="$root/tests/io/framework/sample_test.l0"
d=$(mktemp -d "$(dirname "$1")/framework.XXXXXX")
trap 'rm -rf "$d"' EXIT
cd "$d"
fail() { echo "$*"; exit 1; }
l0() { "$root/tools/l0" "$@"; }

if l0 test "$fixture" > got.tap 2> err; then
    fail "l0 test exited 0 although tests failed"
fi
if ! cmp -s got.tap "$root/tests/io/framework/expected.tap"; then
    echo "the report differs from expected.tap:"
    diff "$root/tests/io/framework/expected.tap" got.tap || true
    exit 1
fi

# --match runs only the tests whose names contain its text.
l0 test "$fixture" --match random > got.tap ||
    fail "a passing selection exited nonzero"
[ "$(sed -n 2p got.tap)" = "1..1" ] || fail "--match did not select one test"
[ "$(sed -n 3p got.tap)" = "ok 1 - test_random_in_range" ] ||
    fail "--match selected the wrong test: $(sed -n 3p got.tap)"

# --bless writes the golden file and says so; afterwards the test passes
# without it, and fails again, with a diff, once the file is changed.
l0 test "$fixture" --match golden --bless > got.tap || fail "--bless failed"
grep -q '^  # ok greeting (blessed golden.txt)$' got.tap ||
    fail "--bless did not report what it wrote"
[ "$(cat golden.txt)" = hello ] || fail "--bless wrote the wrong contents"
l0 test "$fixture" --match golden > got.tap || fail "a blessed golden failed"
printf 'hullo\n' > golden.txt
if l0 test "$fixture" --match golden > got.tap; then
    fail "a changed golden file passed"
fi
grep -q 'first difference at byte 1' got.tap ||
    fail "a changed golden file did not show where it differs"

# The example tests shipped by l0 init must pass, so the first tests a new
# project reads cannot rot.
l0 test "$root/lib/examples.l0" "$root/lib/examples_test.l0" > got.tap ||
    { cat got.tap; fail "lib/examples_test.l0 has failing tests"; }

# A file with no tests is an error, not an empty success.
printf '(def helper () int 0)\n' > none.l0
if l0 test none.l0 > got.tap 2> err; then
    fail "a file with no tests passed"
fi
grep -q 'no tests found' err || fail "no message for a file without tests"
