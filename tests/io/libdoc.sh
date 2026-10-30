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
# l0 spec --path names every file of it, the language first, and each is
# there; l0 spec prints the language, and l0 spec runtime section 10.
spec=$(l0 spec --path | head -n 1)
case "$(head -n 1 "$spec")" in
    "# The L0 Programming Language"*) ;;
    *) fail "l0 spec --path does not name the specification first" ;;
esac
[ "$(l0 spec --path | wc -l)" -ge 6 ] || fail "l0 spec --path does not name every file"
for f in $(l0 spec --path); do
    [ -f "$f" ] || fail "l0 spec --path names $f, which is not there"
done
[ "$(l0 spec | first)" = "$(head -n 1 "$spec")" ] ||
    fail "l0 spec does not print the specification"
l0 spec runtime | grep -q '^### 10.3 Runtime interface' ||
    fail "l0 spec runtime does not print section 10"
# shellcheck disable=SC2046
l0 test $(l0 examples --path) > got.tap ||
    { cat got.tap; fail "the examples' tests fail"; }

# l0 init copies only what an agent's environment needs as files.
l0 init proj > /dev/null
found=$(cd proj && find . -type f | LC_ALL=C sort | tr '\n' ' ')
[ "$found" = "./.cursor/skills/l0-code/SKILL.md ./AGENTS.md " ] ||
    fail "l0 init copied more than AGENTS.md and the skill: $found"

# Run again, l0 init changes only its own part of AGENTS.md, between its
# marker lines, and never a part edited since it wrote it.
begin='<!-- l0 init: begin'
end='<!-- l0 init: end -->'
init_says() { l0 init proj | sed -n 1p; }
cp proj/AGENTS.md part.md
[ "$(init_says)" = "AGENTS.md: already current" ] ||
    fail "l0 init did not see its part was current"
cmp -s part.md proj/AGENTS.md || fail "l0 init changed a current AGENTS.md"

# A stale part, as an older toolchain would have written it, is replaced,
# and the project's lines around it are kept.
sum=$(echo "an older part" | cksum | awk '{ print $1 "-" $2 }')
{ echo "# Our project"; echo "$begin $sum; old -->"; echo "an older part"
  echo "$end"; echo "Our own rule."; } > proj/AGENTS.md
[ "$(init_says)" = "AGENTS.md: l0's part replaced, the rest kept" ] ||
    fail "l0 init did not replace a stale part"
{ echo "# Our project"; cat part.md; echo "Our own rule."; } > want.md
cmp -s want.md proj/AGENTS.md || fail "l0 init lost the project's lines"

# An edited part is kept, and the new one written beside it.
sed "s/^## Commands\$/## Commands, edited/" want.md > proj/AGENTS.md
cp proj/AGENTS.md edited.md
case "$(init_says)" in "AGENTS.md: kept"*) ;; *) fail "l0 init missed an edit" ;; esac
cmp -s edited.md proj/AGENTS.md || fail "l0 init replaced an edited part"
cmp -s part.md proj/AGENTS.md.l0-new || fail "no AGENTS.md.l0-new beside it"
rm proj/AGENTS.md.l0-new

# A project's own AGENTS.md, with no part, gets one after its lines; one
# l0 init wrote whole, before it marked its part, is kept.
echo "Our own rule." > proj/AGENTS.md
[ "$(init_says)" = "AGENTS.md: l0's part added after the project's own" ] ||
    fail "l0 init did not add its part to the project's AGENTS.md"
{ echo "Our own rule."; echo; cat part.md; } > want.md
cmp -s want.md proj/AGENTS.md || fail "l0 init added its part wrongly"
sed '1d;$d' part.md > proj/AGENTS.md
cp proj/AGENTS.md whole.md
case "$(init_says)" in "AGENTS.md: kept"*) ;; *) fail "l0 init missed an old copy" ;; esac
cmp -s whole.md proj/AGENTS.md || fail "l0 init replaced an old copy"
cmp -s part.md proj/AGENTS.md.l0-new || fail "no AGENTS.md.l0-new beside an old copy"
rm proj/AGENTS.md.l0-new
found=$(cd proj && find . -type f | LC_ALL=C sort | tr '\n' ' ')
[ "$found" = "./.cursor/skills/l0-code/SKILL.md ./AGENTS.md " ] ||
    fail "l0 init left files behind: $found"
