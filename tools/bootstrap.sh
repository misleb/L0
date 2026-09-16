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
# When "start" is the stage-0 INTERPRETER, all three stages must be identical.
# The interpreter runs the very same compiler/*.l0 that stage1 is compiled
# from, so both compute the same pure function of the same input, and L0 is
# deterministic. stage1 != stage2 then means the compiler miscompiled itself,
# which is a sharper signal than the fixpoint alone.
#
# That equality would NOT hold if "start" were a different compiler emitting
# equivalent but differently-shaped IR. Only stage2 == stage3 is required in
# general; stage1 == stage2 is an extra check this bootstrap can afford.
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

if [ -f bootstrap/stage2.ll ]; then
    echo "start:  bootstrap/stage2.ll"
    tools/l0ll bootstrap/stage2.ll "$BUILD/l0c-seed"
    run_stage "$BUILD/l0c-seed" "$BUILD/stage1.ll"
    USED_SEED=1
elif [ -x "$BUILD/l0i" ] && [ -f stage0/l0i.c ]; then
    echo "start:  stage0 interpreter (no seed yet)"
    # shellcheck disable=SC2086
    set -- "$BUILD/l0i" run $SOURCES
    printf '#!/bin/sh\nexec' > "$BUILD/stage0-driver"
    for a in "$@"; do printf ' %s' "$a" >> "$BUILD/stage0-driver"; done
    printf ' "$@"\n' >> "$BUILD/stage0-driver"
    chmod +x "$BUILD/stage0-driver"
    run_stage "$BUILD/stage0-driver" "$BUILD/stage1.ll"
    USED_SEED=0
else
    echo "error: no bootstrap entry point." >&2
    echo "  Expected bootstrap/stage2.ll or a stage-0 interpreter." >&2
    exit 1
fi

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

# Only meaningful when stage 1 came from the interpreter; see the header.
if [ "$USED_SEED" = 0 ]; then
    if cmp -s "$BUILD/stage1.ll" "$BUILD/stage2.ll"; then
        echo "AGREEMENT: the compiled compiler matches the interpreted one"
    else
        echo
        echo "FAIL: stage1.ll and stage2.ll differ."
        echo "      The interpreter and the compiled compiler run the same"
        echo "      source, so they must agree. The compiler miscompiled"
        echo "      itself. First difference:"
        diff "$BUILD/stage1.ll" "$BUILD/stage2.ll" | head -20 | sed 's/^/    /'
        exit 1
    fi
fi

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
    mkdir -p bootstrap
    cp "$BUILD/stage2.ll" bootstrap/stage2.ll
    "$CC" --version | head -1 > bootstrap/LLVM-VERSION
    echo "REFRESHED: bootstrap/stage2.ll and bootstrap/LLVM-VERSION written; commit both."
fi
