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

# A test file may define a name lib/test.l0 defines too, and it checks the
# way l0 test builds it: through l0 check --test, and through tools/l0check
# given lib/test.l0.
cat > shadow_test.l0 <<'EOF'
(def first_diff ((xs (list int))) int (length xs))
(def test_shadow () int (check_int "first_diff" (first_diff "abc") 3))
EOF
l0 test shadow_test.l0 > got.tap || { cat got.tap; fail "a shadowing test failed"; }
l0 check --test shadow_test.l0 > /dev/null ||
    fail "l0 check --test rejected what l0 test builds"
"$root/tools/l0check" "$root/lib/prelude.l0" "$root/lib/io.l0" \
    "$root/lib/test.l0" shadow_test.l0 > /dev/null ||
    fail "tools/l0check rejected what l0 test builds"

# l0 run passes what follows -- to the program, even what looks like a file,
# and exits with the program's status.
printf '(def main () int (let w (write_line (arg 0)) (arg_count)))\n' > args.l0
got=$(l0 run args.l0 -- args.l0 b) && st=0 || st=$?
[ "$got" = args.l0 ] || fail "l0 run passed the wrong arguments: $got"
[ "$st" = 2 ] || fail "l0 run exited $st, not the program's 2"

# A test that leaves memory unfreed fails. Correct code cannot leak, so the
# leak comes from a compiler that drops every release.
printf '(def test_allocates () int (check_int "length" (length "abc") 3))\n' \
    > leak_test.l0
l0 test leak_test.l0 > got.tap || { cat got.tap; fail "a test that frees its memory failed"; }
real=${L0_COMPILER:-$root/lib/l0c}
printf '#!/bin/sh\n"%s" | grep -v "call void @l0_dec"\n' "$real" > leaky
chmod +x leaky
if L0_COMPILER="$PWD/leaky" l0 test leak_test.l0 > got.tap; then
    fail "a test that leaked passed"
fi
grep -q 'memory was never freed' got.tap || fail "no message for a leak"

# A file with no tests is an error, not an empty success.
printf '(def helper () int 0)\n' > none.l0
if l0 test none.l0 > got.tap 2> err; then
    fail "a file with no tests passed"
fi
grep -q 'no tests found' err || fail "no message for a file without tests"
