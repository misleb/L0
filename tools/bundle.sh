# Shared by tools/l0c and tools/l0check. Sourced, not executed; ROOT must be
# set by the caller.
#
# write_bundle NOMAIN FILE... writes a compiler input bundle, spec section
# 9.1, to stdout. NOMAIN is 1 to relax the requirement for a main.
#
# When lib/io.l0 or lib/test.l0 is among the files, they and lib/prelude.l0
# are made the prelude group, as tools/l0 makes them, since only the prelude
# may declare the names spec section 7.1 reserves for the standard library,
# and a program may shadow what the prelude defines. lib/test.l0 joins it
# the way l0 test links it, so a test file checks here as it builds there.
# Otherwise every file is the program, which is how the compiler itself is
# built.

abspath() {
    (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")")
}

write_bundle() {
    nomain=$1
    shift
    stdlib=0
    for f in "$@"; do
        case "$(abspath "$f")" in
            "$ROOT/lib/io.l0" | "$ROOT/lib/test.l0") stdlib=1 ;;
        esac
    done
    pre=""
    rest=""
    if [ "$stdlib" = 1 ]; then
        pre_p="$ROOT/lib/prelude.l0"
        pre_i="$ROOT/lib/io.l0"
        pre_t=""
        for f in "$@"; do
            case "$(abspath "$f")" in
                "$ROOT/lib/prelude.l0") pre_p=$f ;;
                "$ROOT/lib/io.l0") pre_i=$f ;;
                "$ROOT/lib/test.l0") pre_t=$f ;;
                *) rest="$rest $f" ;;
            esac
        done
        pre="$pre_p $pre_i $pre_t"
    else
        rest="$*"
    fi
    # shellcheck disable=SC2086
    set -- $pre $rest
    echo "#l0bundle"
    if [ "$nomain" = 1 ]; then
        echo "#nomain"
    fi
    if [ -n "$pre" ]; then
        # shellcheck disable=SC2086
        echo "#prelude $(cat $pre | wc -c | tr -d ' ')"
    fi
    offset=0
    for f in "$@"; do
        echo "$offset $f"
        size=$(wc -c < "$f" | tr -d ' ')
        offset=$((offset + size))
    done
    echo "#source"
    cat "$@"
}
