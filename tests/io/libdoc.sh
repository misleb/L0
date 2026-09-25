#!/bin/sh
# libdoc.sh EXE IR -- what a project learns about L0 from the toolchain
# rather than from copies: l0 doc, l0 spec, l0 examples, and that l0 init
# copies nothing else. EXE and IR are unused.
#
# libdoc/index.txt pins the whole standard-library index. A change to the
# library's public definitions or their ;; comments changes it; regenerate it
# with tools/l0 doc > tests/io/libdoc/index.txt and read the diff.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
d=$(mktemp -d "$(dirname "$1")/libdoc.XXXXXX")
trap 'rm -rf "$d"' EXIT
cd "$d"
fail() { echo "$*"; exit 1; }
l0() { "$root/tools/l0" "$@"; }
first() { sed -n 1p; }

l0 doc > index.txt || fail "l0 doc failed"
if ! cmp -s index.txt "$root/tests/io/libdoc/index.txt"; then
    echo "the index differs from tests/io/libdoc/index.txt:"
    diff "$root/tests/io/libdoc/index.txt" index.txt || true
    exit 1
fi

[ "$(l0 doc next_line | first)" = "io: next_line () IoLine" ] ||
    fail "l0 doc NAME did not show next_line"
case "$(l0 doc IoEnd | first)" in
    "io: (data IoLine "*) ;;
    *) fail "l0 doc CONSTRUCTOR did not show its type" ;;
esac
l0 doc decimal | grep -q '^  prelude: digits ' || fail "l0 doc TEXT did not search"
[ "$(l0 doc test | first)" = "== test" ] || fail "l0 doc FILE did not show the file"

# An internal definition, one without a ;; comment, is never shown.
if l0 doc read_line_onto > out 2> err; then
    fail "l0 doc showed an internal definition: $(cat out)"
fi
grep -q 'nothing in the standard library' err || fail "no message for a miss"

# The specification and examples are the ones this toolchain has.
case "$(head -n 1 "$(l0 spec --path)")" in
    "# The L0 Programming Language"*) ;;
    *) fail "l0 spec --path does not name the specification" ;;
esac
[ "$(l0 spec | first)" = "$(head -n 1 "$(l0 spec --path)")" ] ||
    fail "l0 spec does not print the specification"
# shellcheck disable=SC2046
l0 test $(l0 examples --path) > got.tap ||
    { cat got.tap; fail "the examples' tests fail"; }

# l0 init copies only what an agent's environment needs as files.
l0 init proj > /dev/null
found=$(cd proj && find . -type f | sort | tr '\n' ' ')
[ "$found" = "./.cursor/skills/l0-code/SKILL.md ./AGENTS.md " ] ||
    fail "l0 init copied more than AGENTS.md and the skill: $found"
