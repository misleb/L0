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
# "start" is the seed, bootstrap/stage2.ll: checked-in LLVM IR text, so clang
# alone builds a working compiler without already having one. The first seed
# was cut by starting from the stage-0 interpreter, when all three stages were
# byte-identical; stage 0 cannot run the compiler's source any longer, since
# that source may use anything the seed can compile, so the seed is the only
# start.
#
# When to refresh the seed
# ------------------------
# The seed is a frozen compiler, so it can only compile language features that
# existed when it was frozen. So the seed MUST be refreshed between the two
# steps of the two-step rule (see the l0-bootstrap skill):
#
#   1. teach the compiler to COMPILE a new feature, bootstrap, refresh the seed
#   2. only then start USING that feature in compiler/*.l0 or lib/prelude.l0,
#      and bootstrap again
#
# Using it before the refresh fails at once, here and in tools/l0check, since
# both build the compiler from the checked-in seed. What nothing here shows is
# a refreshed seed left uncommitted: commit bootstrap/stage2.ll at step 1.

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
SOURCES="lib/prelude.l0 $(echo compiler/*.l0)"
if [ "$SOURCES" = "lib/prelude.l0 compiler/*.l0" ]; then
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

# The compiler tags its output "O" or "E" on the first line, so every stage
# goes through run_stage rather than having its stdout captured directly.
# Capturing raw output would write the tag line into the .ll file.
run_stage() {
    compiler=$1
    out=$2
    if "$compiler" < "$SRC" > "$out.tagged"; then
        case "$(head -n 1 "$out.tagged")" in
            O) tail -n +2 "$out.tagged" > "$out" ;;
            E)
                echo "error: the compiler rejected compiler/*.l0:" >&2
                tail -n +2 "$out.tagged" | head -20 >&2
                exit 1
                ;;
            *)
                echo "error: untagged output from $compiler" >&2
                exit 1
                ;;
        esac
    else
        echo "error: $compiler failed" >&2
        exit 1
    fi
}

if [ ! -f bootstrap/stage2.ll ]; then
    echo "error: no bootstrap entry point: bootstrap/stage2.ll is missing." >&2
    exit 1
fi
echo "start:  bootstrap/stage2.ll"
tools/l0ll bootstrap/stage2.ll "$BUILD/l0c-seed.$$"
mv "$BUILD/l0c-seed.$$" "$BUILD/l0c-seed"
run_stage "$BUILD/l0c-seed" "$BUILD/stage1.ll"

# --------------------------------------------- stages 2 and 3: the fixpoint

tools/l0ll "$BUILD/stage1.ll" "$BUILD/stage1"
run_stage "$BUILD/stage1" "$BUILD/stage2.ll"

tools/l0ll "$BUILD/stage2.ll" "$BUILD/stage2"
run_stage "$BUILD/stage2" "$BUILD/stage3.ll"

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

if cmp -s "$BUILD/stage1.ll" bootstrap/stage2.ll; then
    echo "SEED:     up to date (seed reproduces itself from current source)"
else
    echo "SEED:     STALE -- lib/prelude.l0 or compiler/*.l0 has changed since the seed was cut."
    echo "          The seed still compiles this source, so the build works,"
    echo "          but refresh it before using any newly added feature:"
    echo "            tools/bootstrap.sh --refresh-seed"
fi

if [ "$REFRESH" = 1 ]; then
    mkdir -p bootstrap
    cp "$BUILD/stage2.ll" bootstrap/stage2.ll
    "$CC" --version | head -1 > bootstrap/LLVM-VERSION
    echo "REFRESHED: bootstrap/stage2.ll and bootstrap/LLVM-VERSION written; commit both."
fi
