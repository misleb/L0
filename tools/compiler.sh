# Shared by tools/l0c, tools/l0check, and tools/test.sh. Sourced, not
# executed; the caller sets ROOT and sources tools/env.sh first.
#
# current_compiler prints the path of a native compiler built from the
# current lib/prelude.l0 and compiler/*.l0, building it first when they have
# changed since it was last built. It is how the tools run the compiler
# without the stage-0 interpreter, which knows only the L0 of its day and so
# would hold the compiler's own source to it.
#
# The seed, bootstrap/stage2.ll, compiles the source once, with no fixpoint;
# tools/bootstrap.sh and tools/test.sh --compiled check that. Linked at -O0
# this takes under half a second, and the result checks the compiler's own
# source several times faster than stage 0 ran it. A source the seed cannot
# compile, such as one using a feature added since the seed was cut, fails
# here with the seed's diagnostics, at the first check rather than the next
# bootstrap.
#
# Staleness is decided exactly: the bundle the compiler was built from is
# kept beside it and compared byte for byte, and a seed or runtime newer than
# the binary rebuilds it too. Both are written under temporary names and
# renamed into place, the binary first, so a concurrent caller sees the old
# pair, a new binary beside an old bundle (and rebuilds, harmlessly), or the
# new pair.

. "$ROOT/tools/bundle.sh"

# link_quick IR OUT links IR against the runtime at -O0, which is a tenth of
# what tools/l0ll's -O2 -flto costs, for binaries that are rebuilt often and
# run briefly. A tail call is musttail at any level (spec section 8).
link_quick() {
    if [ ! -f "$BUILD/l0rt.o" ] || [ "$ROOT/runtime/l0rt.ll" -nt "$BUILD/l0rt.o" ]; then
        "$ROOT/tools/build.sh" > /dev/null
    fi
    "$CC" -O0 -Wno-override-module "$1" "$BUILD/l0rt.o" -o "$2"
}

current_compiler() {
    cc_bin="$BUILD/l0c-current"
    cc_src="$BUILD/l0c-current.l0"
    cc_tmp="$BUILD/l0c-current.$$"
    mkdir -p "$BUILD"

    # The same files tools/bootstrap.sh compiles, in the same order, as a
    # bundle so that diagnostics name the file they are in.
    # shellcheck disable=SC2046
    (cd "$ROOT" && write_bundle 0 lib/prelude.l0 $(echo compiler/*.l0)) > "$cc_tmp.l0"

    if [ -x "$cc_bin" ] && [ -f "$cc_src" ] && cmp -s "$cc_tmp.l0" "$cc_src" &&
        [ ! "$ROOT/bootstrap/stage2.ll" -nt "$cc_bin" ] &&
        [ ! "$ROOT/runtime/l0rt.ll" -nt "$cc_bin" ]; then
        rm -f "$cc_tmp.l0"
        echo "$cc_bin"
        return 0
    fi

    seed="$BUILD/l0c-seed"
    if [ ! -x "$seed" ] || [ "$ROOT/bootstrap/stage2.ll" -nt "$seed" ] ||
        [ "$ROOT/runtime/l0rt.ll" -nt "$seed" ]; then
        if [ ! -f "$ROOT/bootstrap/stage2.ll" ]; then
            echo "error: no seed at bootstrap/stage2.ll to build the compiler with" >&2
            rm -f "$cc_tmp.l0"
            return 1
        fi
        "$ROOT/tools/l0ll" "$ROOT/bootstrap/stage2.ll" "$cc_tmp.seed"
        mv "$cc_tmp.seed" "$seed"
    fi

    if ! "$seed" < "$cc_tmp.l0" > "$cc_tmp.out"; then
        echo "error: the seed crashed compiling lib/prelude.l0 and compiler/*.l0" >&2
        rm -f "$cc_tmp.l0" "$cc_tmp.out"
        return 1
    fi
    case "$(head -n 1 "$cc_tmp.out")" in
        O) ;;
        *)
            echo "error: the seed, bootstrap/stage2.ll, cannot compile lib/prelude.l0" >&2
            echo "  and compiler/*.l0. If they use a feature the seed predates, the" >&2
            echo "  two-step rule in the l0-bootstrap skill applies:" >&2
            tail -n +2 "$cc_tmp.out" | head -20 | sed 's/^/  /' >&2
            rm -f "$cc_tmp.l0" "$cc_tmp.out"
            return 1
            ;;
    esac
    tail -n +2 "$cc_tmp.out" > "$cc_tmp.ll"
    if ! link_quick "$cc_tmp.ll" "$cc_tmp.bin"; then
        echo "error: the compiler built from source did not link" >&2
        rm -f "$cc_tmp.l0" "$cc_tmp.out" "$cc_tmp.ll" "$cc_tmp.bin"
        return 1
    fi
    mv "$cc_tmp.bin" "$cc_bin"
    mv "$cc_tmp.l0" "$cc_src"
    rm -f "$cc_tmp.out" "$cc_tmp.ll"
    echo "$cc_bin"
}
