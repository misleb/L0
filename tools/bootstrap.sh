#!/bin/sh
# Builds the L0 compiler from the L0 compiler and verifies self-compilation.
#
# Usage: tools/bootstrap.sh [--refresh-seed]
#
#   --refresh-seed   after a successful fixpoint, install the result as
#                    bootstrap/stage2.ll. See "When to refresh the seed" below.
#
# Self-hosting is verified by a byte-for-byte fixpoint, not by judgment:
#
#     start + compiler.l0    ->  stage1.ll  ->  stage1
#     stage1 + compiler.l0   ->  stage2.ll  ->  stage2
#     stage2 + compiler.l0   ->  stage3.ll
#
#     stage2.ll must equal stage3.ll
#
# stage1.ll and stage2.ll are EXPECTED to differ, because "start" and
# compiler.l0 are different programs emitting different but equivalent IR.
# Only the stage2/stage3 comparison means anything.
#
# "start" is whichever bootstrap entry point exists:
#
#   bootstrap/stage2.ll   preferred. Checked-in LLVM IR text, so clang alone can
#                    build a working compiler without already having one.
#   build/l0i        the stage-0 interpreter, used only until the first seed
#                    is committed, after which stage0/ is deleted.
#
# When to refresh the seed
# ------------------------
# The seed is a frozen compiler, so it can only compile language features that
# existed when it was frozen. Once stage0/ is gone, the seed MUST be refreshed
# between the two steps of the two-step rule (see the l0-evolve skill):
#
#   1. teach the compiler to COMPILE a new feature, bootstrap, refresh the seed
#   2. only then start USING that feature in compiler/*.l0, and bootstrap again
#
# Refreshing after both steps is too late. Your working tree will keep building
# because it has a current compiler, while a fresh clone becomes unbuildable
# because the seed never learned the feature. That failure is invisible locally.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"
cd "$ROOT"

REFRESH=0
for arg in "$@"; do
    case "$arg" in
        --refresh-seed) REFRESH=1 ;;
        *)
            echo "usage: tools/bootstrap.sh [--refresh-seed]" >&2
            exit 2
            ;;
    esac
done

# Lexicographic glob order, which is stable, because the compiler's input must
# be byte-identical on every run for the fixpoint to mean anything.
SOURCES=$(echo compiler/*.l0)
if [ "$SOURCES" = "compiler/*.l0" ]; then
    echo "tools/bootstrap.sh: nothing to bootstrap yet."
    echo
    echo "  compiler/*.l0 does not exist, so there is no L0 compiler to"
    echo "  self-compile. This is expected until Phase 2 begins; see README.md."
    echo "  Use tools/test.sh to verify the language itself."
    exit 0
fi

"$ROOT/tools/build.sh" > /dev/null
mkdir -p "$BUILD"

# The compiler reads its source on stdin and writes LLVM IR on stdout. L0 has
# no module system, so concatenation is the whole of "linking" the source.
SRC="$BUILD/compiler-source.l0"
# shellcheck disable=SC2086
cat $SOURCES > "$SRC"
echo "compiler source: $(wc -c < "$SRC" | tr -d ' ') bytes from $(echo $SOURCES | wc -w | tr -d ' ') files"

# ---------------------------------------------------- stage 1: the entry point

if [ -f bootstrap/stage2.ll ]; then
    echo "start:  bootstrap/stage2.ll"
    tools/l0ll bootstrap/stage2.ll "$BUILD/l0c-seed"
    "$BUILD/l0c-seed" < "$SRC" > "$BUILD/stage1.ll"
    USED_SEED=1
elif [ -x "$BUILD/l0i" ] && [ -f stage0/l0i.c ]; then
    echo "start:  stage0 interpreter (no seed yet)"
    # shellcheck disable=SC2086
    "$BUILD/l0i" run $SOURCES < "$SRC" > "$BUILD/stage1.ll"
    USED_SEED=0
else
    echo "error: no bootstrap entry point." >&2
    echo "  Expected bootstrap/stage2.ll or a stage-0 interpreter." >&2
    exit 1
fi

# --------------------------------------------- stages 2 and 3: the fixpoint

tools/l0ll "$BUILD/stage1.ll" "$BUILD/stage1"
"$BUILD/stage1" < "$SRC" > "$BUILD/stage2.ll"

tools/l0ll "$BUILD/stage2.ll" "$BUILD/stage2"
"$BUILD/stage2" < "$SRC" > "$BUILD/stage3.ll"

for s in 1 2 3; do
    echo "stage$s.ll: $(wc -c < "$BUILD/stage$s.ll" | tr -d ' ') bytes"
done

if ! cmp -s "$BUILD/stage2.ll" "$BUILD/stage3.ll"; then
    echo
    echo "FAIL: stage2.ll and stage3.ll differ, so the compiler does not"
    echo "      compile itself to itself."
    echo
    echo "First difference:"
    diff "$BUILD/stage2.ll" "$BUILD/stage3.ll" | head -20 | sed 's/^/    /'
    echo
    echo "Check nondeterminism first: the same binary must produce the same"
    echo "bytes twice. See the l0-bootstrap skill."
    exit 1
fi

echo
echo "FIXPOINT: stage2.ll == stage3.ll ($(wc -c < "$BUILD/stage2.ll" | tr -d ' ') bytes)"

# ------------------------------------------------------------ seed handling

if [ "$USED_SEED" = 1 ]; then
    if cmp -s "$BUILD/stage1.ll" bootstrap/stage2.ll; then
        echo "SEED:     up to date (seed reproduces itself from current source)"
    else
        echo "SEED:     STALE -- compiler/*.l0 has changed since the seed was cut."
        echo "          The seed still compiles this source, so the build works,"
        echo "          but refresh it before using any newly added feature:"
        echo "            tools/bootstrap.sh --refresh-seed"
    fi
fi

if [ "$REFRESH" = 1 ]; then
    mkdir -p seed
    cp "$BUILD/stage2.ll" bootstrap/stage2.ll
    "$CC" --version | head -1 > bootstrap/LLVM-VERSION
    echo "REFRESHED: bootstrap/stage2.ll and bootstrap/LLVM-VERSION written; commit both."
fi
