#!/bin/sh
# Runs the golden test suites.
#
# Usage: tools/test.sh [--bless] [name-filter]
#
#   --bless   overwrite expectation files with whatever the code produces now.
#             Use after deliberately changing behavior or wording, then read
#             the resulting git diff to confirm every change was intended.
#
# Suites:
#   tests/backend/*.ll   hand-written IR linked against the runtime, pinning
#                        down the ABI in spec section 10
#   tests/lang/*.l0      programs that must type check and run
#   tests/check/*.l0     programs that must fail to type check
#
# Per-test files, where <stem> is the test path without its extension:
#   <stem>.out     expected stdout, required, may be empty
#   <stem>.err     expected stderr; if absent, stderr must be empty
#   <stem>.exit    expected exit status; if absent, 0
#   <stem>.in      stdin; if absent, empty
#   <stem>.extra   additional source files to pass, one per line

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"
cd "$ROOT" # so diagnostics contain stable relative paths

BLESS=0
FILTER=""
for arg in "$@"; do
    case "$arg" in
        --bless) BLESS=1 ;;
        -*)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
        *) FILTER=$arg ;;
    esac
done

"$ROOT/tools/build.sh" > /dev/null

# The lang and check suites run through the stage-0 interpreter. When stage0/
# is deleted they will need to be repointed at the L0 compiler; until that is
# done, say so rather than reporting a pile of confusing failures.
if [ ! -x "$BUILD/l0i" ]; then
    echo "error: tests/lang and tests/check need an L0 implementation to run," >&2
    echo "  and stage0/ has been deleted. Repoint this script at the compiler" >&2
    echo "  built by tools/bootstrap.sh." >&2
    exit 1
fi

TMP="$BUILD/test-tmp"
rm -rf "$TMP"
mkdir -p "$TMP"

npass=0
nfail=0
failures=""

# run_case SUITE NAME STEM COMMAND...
run_case() {
    suite=$1
    name=$2
    stem=$3
    shift 3

    out_file="$stem.out"
    err_file="$stem.err"
    exit_file="$stem.exit"
    in_file="$stem.in"

    if [ -f "$in_file" ]; then
        stdin_source="$in_file"
    else
        stdin_source=/dev/null
    fi

    set +e
    "$@" < "$stdin_source" > "$TMP/out" 2> "$TMP/err"
    got_exit=$?
    set -e

    if [ "$BLESS" = 1 ]; then
        cp "$TMP/out" "$out_file"
        if [ -s "$TMP/err" ]; then
            cp "$TMP/err" "$err_file"
        else
            rm -f "$err_file"
        fi
        if [ "$got_exit" -ne 0 ]; then
            echo "$got_exit" > "$exit_file"
        else
            rm -f "$exit_file"
        fi
        echo "bless $suite/$name"
        npass=$((npass + 1))
        return 0
    fi

    want_exit=0
    if [ -f "$exit_file" ]; then
        want_exit=$(cat "$exit_file")
    fi

    why=""
    if [ ! -f "$out_file" ]; then
        why="no expectation file; run tools/test.sh --bless"
    elif ! cmp -s "$TMP/out" "$out_file"; then
        why="stdout differs"
    elif [ -f "$err_file" ] && ! cmp -s "$TMP/err" "$err_file"; then
        why="stderr differs"
    elif [ ! -f "$err_file" ] && [ -s "$TMP/err" ]; then
        why="unexpected stderr"
    elif [ "$got_exit" != "$want_exit" ]; then
        why="exit status $got_exit, expected $want_exit"
    fi

    if [ -z "$why" ]; then
        npass=$((npass + 1))
        return 0
    fi

    nfail=$((nfail + 1))
    failures="$failures $suite/$name"
    echo "FAIL $suite/$name: $why"
    case "$why" in
        "stdout differs")
            diff -u "$out_file" "$TMP/out" | sed 's/^/    /' || true
            ;;
        "stderr differs")
            diff -u "$err_file" "$TMP/err" | sed 's/^/    /' || true
            ;;
        "unexpected stderr")
            sed 's/^/    /' "$TMP/err"
            ;;
    esac
    return 0
}

selected() {
    if [ -z "$FILTER" ]; then
        return 0
    fi
    case "$1" in
        *"$FILTER"*) return 0 ;;
        *) return 1 ;;
    esac
}

extra_sources() {
    if [ -f "$1.extra" ]; then
        tr '\n' ' ' < "$1.extra"
    fi
}

# ------------------------------------------------------------------ backend

for src in tests/backend/*.ll; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .ll)
    selected "$name" || continue
    stem="tests/backend/$name"
    exe="$TMP/backend-$name"

    if ! "$CC" -O2 -Wno-override-module "$src" "$BUILD/l0rt.o" \
        "$BUILD/l0core.o" -o "$exe" 2> "$TMP/link.err"; then
        nfail=$((nfail + 1))
        failures="$failures backend/$name"
        echo "FAIL backend/$name: link failed"
        sed 's/^/    /' "$TMP/link.err"
        continue
    fi
    run_case backend "$name" "$stem" "$exe"
done

# --------------------------------------------------------------------- lang

for src in tests/lang/*.l0; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .l0)
    selected "$name" || continue
    stem="tests/lang/$name"
    # Unquoted on purpose: extra sources are a whitespace-separated list.
    # shellcheck disable=SC2046
    run_case lang "$name" "$stem" "$BUILD/l0i" run "$src" $(extra_sources "$stem")
done

# ----------------------------------------------------------------- compiler

# Compiler stage tests. Each supplies its own main and names the compiler
# sources it needs in a .extra file, so a lexer test can link lex.l0 without
# pulling in the compiler's own main.
for src in tests/compiler/*.l0; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .l0)
    case "$name" in
        fmt) continue ;; # shared helper, not a test
    esac
    selected "$name" || continue
    stem="tests/compiler/$name"
    # shellcheck disable=SC2046
    run_case compiler "$name" "$stem" "$BUILD/l0i" run "$src" $(extra_sources "$stem")
done

# -------------------------------------------------------------------- check

for src in tests/check/*.l0; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .l0)
    selected "$name" || continue
    stem="tests/check/$name"
    # shellcheck disable=SC2046
    run_case check "$name" "$stem" "$BUILD/l0i" check "$src" $(extra_sources "$stem")
done

# ------------------------------------------------------------------ summary

echo
if [ "$nfail" -eq 0 ]; then
    echo "all $npass tests passed"
    exit 0
fi
echo "$npass passed, $nfail failed:"
for f in $failures; do
    echo "  $f"
done
exit 1
