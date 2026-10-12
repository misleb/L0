#!/bin/sh
# Runs the golden test suites.
#
# Usage: tools/test.sh [--compiled] [--bless | --compiled --bless-check] [name-filter]
#
#   --compiled     bootstrap the current compiler and run the suites through it,
#                  with tests/io and tests/unit, which stage 0 cannot run
#   --bless        overwrite expectation files with whatever the code produces
#                  now. Use after deliberately changing behavior or wording,
#                  then read the resulting git diff to confirm every change was
#                  intended. Refused with --compiled.
#   --bless-check  with --compiled: rewrite tests/check's .cerr files, the
#                  compiler's own diagnostics
#   --virt         run tests/virt on QEMU's virt board, with no operating
#                  system, through tools/l0 build --target virt, and again
#                  as processes of a kernel, through --target proc; needs
#                  qemu-system-aarch64, and Docker or L0_VIRT_LD
#   name-filter    a substring of a test's file name without its directory or
#                  extension, such as bundle_prelude, matched in every suite.
#                  A filter that matches nothing passes, with "0 tests".
#
# Suites:
#   tests/backend/*.ll   hand-written IR linked against the runtime, pinning
#                        down the ABI in spec section 10
#   tests/lang/*.l0      programs that must type check and run
#   tests/compiler/*.l0  the compiler's own stage tests, which link its
#                        source; built by the current compiler
#                        (tools/compiler.sh), never run by stage 0
#   tests/check/*.l0     programs that must fail to type check
#   tests/io/*.l0        programs using features stage 0 does not have, such
#                        as the I/O builtins; run by --compiled only
#   tests/unit/*_test.l0 tests written with l0 test; run by --compiled, and by
#                        --virt on the board, each file counting as one test
#   tests/virt/unit/*_test.l0
#                        tests written with l0 test of what only the board has;
#                        run by --virt only
#   tests/virt/*.l0      programs run on the virt board, against hand-written
#                        expectations, and as processes of a kernel against
#                        the same; run by --virt only
#   tests/virt/proc/*.l0 programs run only as processes, under the kernel
#                        in tests/virt/proc/harness; run by --virt only
#
# Per-test files, where <stem> is the test path without its extension:
#   <stem>.out     expected stdout, required, may be empty
#   <stem>.err     expected stderr; if absent, stderr must be empty
#   <stem>.exit    expected exit status; if absent, 0
#   <stem>.in      stdin; if absent, empty
#   <stem>.cat     instead of .in: files to concatenate as stdin, one per
#                  line, so a test of repository files reads them as they
#                  are rather than a copy that can go stale
#   <stem>.extra   additional source files to pass, one per line
#   <stem>.cerr    tests/check only: the compiler's diagnostics, compared by
#                  --compiled and rewritten by --compiled --bless-check
#   <stem>.sh      tests/io only: run as `sh <stem>.sh EXE IR` instead of
#                  comparing output, for behavior that is about timing or
#                  about how the program is built, where IR is the file EXE
#                  was linked from; exit status 0 is a pass
#   <stem>.host    why the program needs a host with files or arguments, or
#                  one without devices; --virt skips it
#   <stem>.board   tests/virt only: why the program needs the board itself, such
#                  as its user mode; it is not run again as a process
#   <stem>.args    tests/virt/proc only: the process's arguments, one per line
#   <stem>.with    tests/virt/proc only: what the kernel runs beside it, one
#                  per line, spin or fault from tests/virt/proc/harness
#   <stem>.procs   tests/virt/user only: the processes kernel.l0 runs, in
#                  order, an L0 program by its path or harness IR by name
#
# tests/io has no oracle, since stage 0 cannot run it, so its expectations
# are written by hand and never blessed: --bless skips the suite, and it is
# not run at all without --compiled.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"
. "$ROOT/tools/compiler.sh"
cd "$ROOT" # so diagnostics contain stable relative paths

BLESS=0
BLESS_CHECK=0
COMPILED=0
VIRT=0
FILTER=""
for arg in "$@"; do
    case "$arg" in
        --bless) BLESS=1 ;;
        --bless-check) BLESS_CHECK=1 ;;
        --compiled) COMPILED=1 ;;
        --virt) VIRT=1 ;;
        -*)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
        *) FILTER=$arg ;;
    esac
done

if [ "$COMPILED" = 1 ] && [ "$BLESS" = 1 ]; then
    echo "--compiled and --bless are mutually exclusive: the compiled suite" >&2
    echo "  is judged against the interpreter's expectations, so blessing it" >&2
    echo "  from compiler output would destroy the differential property." >&2
    echo "  To update the compiler's own diagnostics for tests/check, use" >&2
    echo "  --compiled --bless-check." >&2
    exit 2
fi

if [ "$VIRT" = 1 ] && { [ "$BLESS" = 1 ] || [ "$COMPILED" = 1 ]; }; then
    echo "--virt runs alone, and tests/virt's expectations are written by hand," >&2
    echo "  as tests/io's are, so they are never blessed" >&2
    exit 2
fi

if [ "$BLESS_CHECK" = 1 ] && [ "$COMPILED" = 0 ]; then
    echo "--bless-check applies to the compiled suite; add --compiled" >&2
    exit 2
fi

"$ROOT/tools/build.sh" > /dev/null

# The lang and check suites run through the stage-0 interpreter, the oracle
# the compiled suite judges the compiler's output against. If stage0/ is ever
# deleted they will need another oracle; until then, say so rather than
# reporting a pile of confusing failures.
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

# run_case SUITE NAME STEM COMMAND... runs a test and judges it.
run_case() {
    suite=$1
    name=$2
    stem=$3
    shift 3
    exec_case "$TMP/run" "$stem" "$@"
    judge_case "$suite" "$name" "$stem" "$TMP/run"
}

# exec_case RES STEM COMMAND... runs a test on its stdin and leaves what it
# did in RES.out, RES.err, and RES.exit. It touches nothing else, so tests
# with different RES can run at once.
exec_case() {
    res=$1
    stem=$2
    shift 2
    if [ -f "$stem.cat" ]; then
        # shellcheck disable=SC2046
        cat $(cat "$stem.cat") > "$res.in"
        stdin_source="$res.in"
    elif [ -f "$stem.in" ]; then
        stdin_source="$stem.in"
    else
        stdin_source=/dev/null
    fi
    set +e
    "$@" < "$stdin_source" > "$res.out" 2> "$res.err"
    echo $? > "$res.exit"
    set -e
}

# judge_case SUITE NAME STEM RES compares what exec_case left in RES with the
# test's expectations, or blesses it, and counts the result.
judge_case() {
    suite=$1
    name=$2
    stem=$3
    res=$4

    out_file="$stem.out"
    err_file="$stem.err"
    exit_file="$stem.exit"
    got_exit=$(cat "$res.exit")

    if [ "$BLESS" = 1 ]; then
        cp "$res.out" "$out_file"
        if [ -s "$res.err" ]; then
            cp "$res.err" "$err_file"
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
    elif ! cmp -s "$res.out" "$out_file"; then
        why="stdout differs"
    elif [ -f "$err_file" ] && ! cmp -s "$res.err" "$err_file"; then
        why="stderr differs"
    elif [ ! -f "$err_file" ] && [ -s "$res.err" ]; then
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
            diff -u "$out_file" "$res.out" | sed 's/^/    /' || true
            ;;
        "stderr differs")
            diff -u "$err_file" "$res.err" | sed 's/^/    /' || true
            ;;
        "unexpected stderr")
            sed 's/^/    /' "$res.err"
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

# --------------------------------------------------------------------- virt
#
# The fixpoint's last step on QEMU's aarch64 virt board, and then the
# compiled suite's programs there, a host without an operating system (spec
# section 9.2), against the very expectations
# --compiled holds them to: tests/lang, tests/compiler, and tests/io, each
# compiled by the current compiler with tools/l0c, linked with tools/l0
# link --target virt, and booted with tools/l0 boot; and tests/unit, by
# tools/l0 test --target virt. Then tests/virt, the board's own, built with
# tools/l0 build --target virt, and tests/virt/unit, by l0 test there too.
#
# What skips, rather than failing, is what needs a host the board is not:
#   - a tests/io program with a .sh script, which examines the program
#     through the host: its files, arguments, signals, timing, or how it
#     was built
#   - a program, or a tests/unit file, with a <stem>.host file, which says
#     why it needs files or
#     arguments the board does not have, or no devices where the board has
#     them, and so expectations the board cannot meet. A new one without a
#     script gets a .host file, or fails here.
# The board has no environment, so L0_RC_CHECK, which --compiled sets, is
# not checked here.
#
# Every image is linked by one container, started once and given each link
# by docker exec, rather than a docker run per image, unless L0_VIRT_LD
# already names a linker.

if [ "$VIRT" = 1 ]; then
    vstart=$(date +%s)
    vdir="$BUILD/virt"
    pdir="$BUILD/proc"
    if [ ! -f "$vdir/host.bc" ] || [ ! -f "$pdir/host.bc" ]; then
        echo "FAIL: $CC cannot build the aarch64 runtimes for --target virt and proc"
        exit 1
    fi
    vcc=$(current_compiler)
    if [ -z "${L0_VIRT_LD:-}" ]; then
        if ! docker image inspect l0-virt-link > /dev/null 2>&1; then
            docker build -q -t l0-virt-link tools/virt > /dev/null
        fi
        vname="l0-virt-test-$$"
        docker run -d --rm --name "$vname" -v "$ROOT:$ROOT" l0-virt-link \
            sleep 86400 > /dev/null
        trap 'docker stop -t 0 "$vname" > /dev/null 2>&1 || true' EXIT
        # The repository is mounted at its own path, so every path tools/l0
        # passes means the same inside.
        printf '#!/bin/sh\nexec docker exec -w "$PWD" %s ld.lld "$@"\n' \
            "$vname" > "$TMP/virt-ld"
        chmod +x "$TMP/virt-ld"
        L0_VIRT_LD="$TMP/virt-ld"
    fi
    L0_VIRT_DIR="$vdir"
    L0_PROC_DIR="$pdir"
    export L0_VIRT_LD L0_VIRT_DIR L0_PROC_DIR

    # First the goal's measure: the compiler compiles itself on the board,
    # and as a process, to the bytes it writes here (tools/bootstrap.sh
    # --virt).
    if ./tools/bootstrap.sh --virt > "$TMP/bootstrap.log" 2>&1; then
        npass=$((npass + 1))
    else
        nfail=$((nfail + 1))
        failures="$failures virt/fixpoint"
        echo "FAIL virt/fixpoint: tools/bootstrap.sh --virt failed"
        sed 's/^/    /' "$TMP/bootstrap.log"
    fi

    # virt_case SUITE NAME SRC STEM builds SRC for the board and judges it.
    virt_case() {
        vsuite=$1
        vname_=$2
        vsrc=$3
        vstem=$4
        # shellcheck disable=SC2046
        if ! ./tools/l0c "$vsrc" $(extra_sources "$vstem") > "$TMP/$vname_.ll" \
            2> "$TMP/$vname_.cerr"; then
            nfail=$((nfail + 1))
            failures="$failures $vsuite/$vname_"
            echo "FAIL $vsuite/$vname_: compiler rejected a valid program"
            sed 's/^/    /' "$TMP/$vname_.cerr"
            return
        fi
        if ! ./tools/l0 link --target virt "$TMP/$vname_.ll" -o "$TMP/$vname_.elf" \
            > "$TMP/$vname_.lerr" 2>&1; then
            nfail=$((nfail + 1))
            failures="$failures $vsuite/$vname_"
            echo "FAIL $vsuite/$vname_: did not link for the board"
            sed 's/^/    /' "$TMP/$vname_.lerr"
            return
        fi
        run_case "$vsuite" "$vname_" "$vstem" ./tools/l0 boot "$TMP/$vname_.elf"
    }

    nskip=0
    for src in tests/lang/*.l0 tests/compiler/*.l0 tests/io/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        dir=$(dirname "$src")
        case "$dir/$name" in tests/compiler/fmt) continue ;; esac
        selected "$name" || continue
        stem="$dir/$name"
        if [ -f "$stem.sh" ] || [ -f "$stem.host" ]; then
            nskip=$((nskip + 1))
            continue
        fi
        virt_case "virt-$(basename "$dir")" "$name" "$src" "$stem"
    done
    # Tests written with l0 test, on the board with l0 test --target virt,
    # each file in a scratch directory as --compiled runs them: tests/unit's
    # but for those with a .host file, and tests/virt/unit's, the board's
    # own.
    for src in tests/unit/*_test.l0 tests/virt/unit/*_test.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        ustem="${src%.l0}"
        if [ -f "$ustem.host" ]; then
            nskip=$((nskip + 1))
            continue
        fi
        udir="$TMP/vunit-$name"
        mkdir -p "$udir"
        # shellcheck disable=SC2046
        if (cd "$udir" && L0_COMPILER="$vcc" "$ROOT/tools/l0" test --target virt \
            "$ROOT/$src" $(extra_sources "$ROOT/$ustem" | sed "s|[^ ][^ ]*|$ROOT/&|g")) \
            > "$udir.tap" 2>&1; then
            npass=$((npass + 1))
        else
            nfail=$((nfail + 1))
            failures="$failures virt-unit/$name"
            echo "FAIL virt-unit/$name:"
            grep -v '^ok ' "$udir.tap" | sed 's/^/    /'
        fi
    done

    for src in tests/virt/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="tests/virt/$name"
        # shellcheck disable=SC2046
        if ! L0_COMPILER="$vcc" ./tools/l0 build --target virt "$src" \
            $(extra_sources "$stem") -o "$TMP/$name.elf" \
            > "$TMP/$name.berr" 2>&1; then
            nfail=$((nfail + 1))
            failures="$failures virt/$name"
            echo "FAIL virt/$name: did not build"
            sed 's/^/    /' "$TMP/$name.berr"
            continue
        fi
        run_case virt "$name" "$stem" ./tools/l0 boot "$TMP/$name.elf"
    done

    # The same programs, but for those a .board file keeps on the board, as
    # processes of a kernel (spec section 9.2), each
    # built with tools/l0 build --target proc and run alone, as the first
    # process of tests/virt/proc/harness/kernel.ll, against the board's
    # expectations: that kernel gives no files, arguments, or environment,
    # which is what the board gives, and maps the board's devices. Then
    # tests/virt/proc, the process host's own, with the arguments and the
    # processes beside it that its .args and .with files give.
    pwork="$TMP/proc"
    harness=tests/virt/proc/harness

    # proc_build SUITE NAME SRC STEM builds SRC as a process image, or
    # fails the test.
    proc_build() {
        # shellcheck disable=SC2046
        if L0_COMPILER="$vcc" ./tools/l0 build --target proc "$3" \
            $(extra_sources "$4") -o "$TMP/$2.proc.elf" \
            > "$TMP/$2.proc.berr" 2>&1; then
            return 0
        fi
        nfail=$((nfail + 1))
        failures="$failures $1/$2"
        echo "FAIL $1/$2: did not build as a process"
        sed 's/^/    /' "$TMP/$2.proc.berr"
        return 1
    }

    for src in tests/virt/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="tests/virt/$name"
        [ -f "$stem.board" ] && continue
        proc_build virt-proc "$name" "$src" "$stem" || continue
        run_case virt-proc "$name" "$stem" "$harness/boot.sh" "$pwork" - \
            "$TMP/$name.proc.elf"
    done

    spin=""
    for src in tests/virt/proc/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="tests/virt/proc/$name"
        proc_build proc "$name" "$src" "$stem" || continue
        args=-
        [ -f "$stem.args" ] && args="$stem.args"
        beside=""
        if [ -f "$stem.with" ]; then
            for w in $(cat "$stem.with"); do
                case $w in
                    spin)
                        if [ -z "$spin" ]; then
                            proc_build proc spin "$harness/spin.l0" "$harness/spin" || continue 2
                            spin="$TMP/spin.proc.elf"
                        fi
                        beside="$beside $spin"
                        ;;
                    *) beside="$beside $w" ;;
                esac
            done
        fi
        # shellcheck disable=SC2086
        run_case proc "$name" "$stem" "$harness/boot.sh" "$pwork" "$args" \
            "$TMP/$name.proc.elf" $beside
    done

    # And under a kernel written in L0 (spec sections 6.13 and 6.14): each
    # tests/virt program, as built above, the one process of
    # tests/virt/user/kernel.l0, against the board's expectations once more;
    # then tests/virt/user's own, each a NAME.procs file naming its
    # processes in order, an L0 program by its path or the harness's IR by
    # its name, such as fault, which the kernel must kill; then
    # tests/virt/proc's, beside what their .with files name, as under the
    # harness, but for those given arguments, which this kernel gives none.
    user=tests/virt/user
    uwork="$TMP/user"
    mkdir -p "$uwork"

    # user_ir NAME links the harness's NAME.ll as a process, into
    # $uwork/NAME.elf, or fails the test of that name.
    user_ir() {
        if [ -f "$uwork/$1.elf" ]; then
            return 0
        fi
        if { "$CC" --target=aarch64-none-elf -O2 -c "$harness/$1.ll" -o "$uwork/$1.o" &&
            "$L0_VIRT_LD" -T runtime/proc.ld "$uwork/$1.o" -o "$uwork/$1.elf"; } \
            > "$uwork/$1.berr" 2>&1; then
            return 0
        fi
        nfail=$((nfail + 1))
        failures="$failures user/$1"
        echo "FAIL user/$1: did not build"
        sed 's/^/    /' "$uwork/$1.berr"
        return 1
    }
    if ! L0_COMPILER="$vcc" ./tools/l0 build --target virt "$user/kernel.l0" \
        -o "$uwork/kernel.elf" > "$uwork/kernel.berr" 2>&1; then
        nfail=$((nfail + 1))
        failures="$failures virt-user/kernel"
        echo "FAIL virt-user/kernel: did not build"
        sed 's/^/    /' "$uwork/kernel.berr"
    else
        for src in tests/virt/*.l0; do
            [ -f "$src" ] || continue
            name=$(basename "$src" .l0)
            selected "$name" || continue
            [ -f "$TMP/$name.proc.elf" ] || continue
            run_case virt-user "$name" "tests/virt/$name" "$user/run.sh" \
                "$uwork/kernel.elf" "$uwork" "$TMP/$name.proc.elf"
        done
        for spec in "$user"/*.procs; do
            [ -f "$spec" ] || continue
            name=$(basename "$spec" .procs)
            selected "$name" || continue
            images=""
            for p in $(cat "$spec"); do
                case $p in
                    *.l0)
                        pn=$(basename "$p" .l0)
                        proc_build user "$pn" "$p" "${p%.l0}" || continue 2
                        images="$images $TMP/$pn.proc.elf"
                        ;;
                    *)
                        user_ir "$p" || continue 2
                        images="$images $uwork/$p.elf"
                        ;;
                esac
            done
            # shellcheck disable=SC2086
            run_case user "$name" "$user/$name" "$user/run.sh" \
                "$uwork/kernel.elf" "$uwork" $images
        done
        for src in tests/virt/proc/*.l0; do
            [ -f "$src" ] || continue
            name=$(basename "$src" .l0)
            selected "$name" || continue
            stem="tests/virt/proc/$name"
            [ -f "$stem.args" ] && continue
            [ -f "$TMP/$name.proc.elf" ] || continue
            beside=""
            if [ -f "$stem.with" ]; then
                for w in $(cat "$stem.with"); do
                    case $w in
                        spin) beside="$beside $TMP/spin.proc.elf" ;;
                        *)
                            user_ir "$w" || continue 2
                            beside="$beside $uwork/$w.elf"
                            ;;
                    esac
                done
            fi
            # shellcheck disable=SC2086
            run_case user-proc "$name" "$stem" "$user/run.sh" \
                "$uwork/kernel.elf" "$uwork" "$TMP/$name.proc.elf" $beside
        done
    fi

    echo
    echo "virt suite: $npass passed, $nfail failed, $nskip skipped, in $(( $(date +%s) - vstart )) s"
    if [ "$nfail" -ne 0 ]; then
        for f in $failures; do echo "  $f"; done
        exit 1
    fi
    exit 0
fi

# ----------------------------------------------------------------- compiled
#
# Differential testing: compile each tests/lang program with the L0 compiler,
# link it, run it, and compare against the very same expectations the stage-0
# interpreter is held to. The oracle is an independent implementation rather
# than expectations written by whoever wrote the compiler, which is what makes
# this the strongest signal available.
#
# Programs the compiler cannot handle yet report "not supported by this
# compiler yet" and are skipped. Nothing is hardcoded, so coverage grows on
# its own as the compiler gains features. Any OTHER compile failure is a real
# failure: the interpreter accepts the program, so the compiler must too.

if [ "$COMPILED" = 1 ]; then
    # Test the CURRENT compiler, not whatever the checked-in seed happens to
    # hold. Bootstrapping from source first is the only way to be sure of
    # that, and it makes --compiled verify the fixpoint as a side effect.
    # Using a stale seed here would silently test an old compiler.
    rm -f "$BUILD/l0c-native"
    if ! ./tools/bootstrap.sh > "$TMP/bootstrap.log" 2>&1; then
        echo "FAIL: bootstrap failed, so there is no compiler to test with"
        sed 's/^/    /' "$TMP/bootstrap.log"
        exit 1
    fi
    cp "$BUILD/stage2" "$BUILD/l0c-native"

    # Every compiled program in this suite runs with reference counting
    # checked: a block still live at a normal exit, or a freed block used
    # again, is reported on standard error, which fails the test. And
    # tools/l0, used by the scripted tests, compiles with the compiler just
    # built rather than the installed one.
    L0_RC_CHECK=1
    L0_COMPILER="$BUILD/l0c-native"
    L0_RUNTIME="$BUILD/l0rt.o"
    L0_HOST="$BUILD/l0host.o"
    export L0_RC_CHECK L0_COMPILER L0_RUNTIME L0_HOST

    nskip=0

    # build_exe SUITE NAME SRC STEM -> 0 built, 1 failed, 2 unsupported
    build_exe() {
        bsuite=$1
        bname=$2
        bsrc=$3
        bstem=$4
        # shellcheck disable=SC2046
        if ! ./tools/l0c "$bsrc" $(extra_sources "$bstem") > "$TMP/$bname.ll" \
            2> "$TMP/$bname.cerr"; then
            if grep -q "not supported by this compiler yet" \
                "$TMP/$bname.cerr"; then
                return 2
            fi
            nfail=$((nfail + 1))
            failures="$failures $bsuite/$bname"
            echo "FAIL $bsuite/$bname: compiler rejected a valid program"
            sed 's/^/    /' "$TMP/$bname.cerr"
            return 1
        fi
        if ! ./tools/l0ll "$TMP/$bname.ll" "$TMP/$bname.exe" \
            2> "$TMP/$bname.lerr"; then
            nfail=$((nfail + 1))
            failures="$failures $bsuite/$bname"
            echo "FAIL $bsuite/$bname: generated IR did not assemble"
            sed 's/^/    /' "$TMP/$bname.lerr"
            return 1
        fi
        return 0
    }

    # Programs that must run. Judged against the interpreter's expectations,
    # which is what makes this differential rather than self-referential.
    for src in tests/lang/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="tests/lang/$name"
        build_exe compiled "$name" "$src" "$stem"
        case $? in
            2) nskip=$((nskip + 1)); continue ;;
            1) continue ;;
        esac
        run_case compiled "$name" "$stem" "$TMP/$name.exe"
    done

    # Compiler stage tests, against the very same goldens the interpreted run
    # uses. These are pure functions of stdin, so any difference at all means
    # the two implementations disagree.
    for src in tests/compiler/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        case "$name" in fmt) continue ;; esac
        selected "$name" || continue
        stem="tests/compiler/$name"
        build_exe compiled "$name" "$src" "$stem"
        case $? in
            2) nskip=$((nskip + 1)); continue ;;
            1) continue ;;
        esac
        run_case compiled "$name" "$stem" "$TMP/$name.exe"
    done

    # Programs that must be REJECTED. The compiler's wording differs from the
    # interpreter's, so these have their own .cerr expectations; what matters
    # is that every program the interpreter rejects, the compiler rejects too.
    for src in tests/check/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        cerr="tests/check/$name.cerr"

        if ./tools/l0c "$src" > /dev/null 2> "$TMP/$name.cerr"; then
            nfail=$((nfail + 1))
            failures="$failures compiled-check/$name"
            echo "FAIL compiled-check/$name: compiler ACCEPTED a program the interpreter rejects"
            continue
        fi

        if [ "$BLESS_CHECK" = 1 ]; then
            cp "$TMP/$name.cerr" "$cerr"
            echo "bless compiled-check/$name"
            npass=$((npass + 1))
            continue
        fi
        if [ ! -f "$cerr" ]; then
            nfail=$((nfail + 1))
            failures="$failures compiled-check/$name"
            echo "FAIL compiled-check/$name: no expectation file"
        elif ! cmp -s "$TMP/$name.cerr" "$cerr"; then
            nfail=$((nfail + 1))
            failures="$failures compiled-check/$name"
            echo "FAIL compiled-check/$name: diagnostics differ"
            diff -u "$cerr" "$TMP/$name.cerr" | sed 's/^/    /' || true
        else
            npass=$((npass + 1))
        fi
    done

    # Programs stage 0 cannot run, judged against hand-written expectations,
    # or by a script when what matters is when output appears.
    for src in tests/io/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="tests/io/$name"
        build_exe io "$name" "$src" "$stem"
        case $? in
            2) nskip=$((nskip + 1)); continue ;;
            1) continue ;;
        esac
        if [ -f "$stem.sh" ]; then
            if sh "$stem.sh" "$TMP/$name.exe" "$TMP/$name.ll" \
                > "$TMP/$name.shout" 2>&1; then
                npass=$((npass + 1))
            else
                nfail=$((nfail + 1))
                failures="$failures io/$name"
                echo "FAIL io/$name: $stem.sh failed"
                sed 's/^/    /' "$TMP/$name.shout"
            fi
        else
            run_case io "$name" "$stem" "$TMP/$name.exe"
        fi
    done

    # Tests written with l0 test, each file run in a scratch directory so the
    # files its tests write stay out of the repository, and against the
    # compiler and runtime just built rather than the installed ones.
    for src in tests/unit/*_test.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        udir="$TMP/unit-$name"
        mkdir -p "$udir"
        # shellcheck disable=SC2046
        if (cd "$udir" && L0_COMPILER="$BUILD/l0c-native" \
            L0_RUNTIME="$BUILD/l0rt.o" L0_HOST="$BUILD/l0host.o" \
            "$ROOT/tools/l0" test "$ROOT/$src" \
            $(extra_sources "$ROOT/tests/unit/$name" | sed "s|[^ ][^ ]*|$ROOT/&|g")) \
            > "$udir.tap" 2>&1; then
            npass=$((npass + 1))
        else
            nfail=$((nfail + 1))
            failures="$failures unit/$name"
            echo "FAIL unit/$name:"
            grep -v '^ok ' "$udir.tap" | sed 's/^/    /'
        fi
    done

    echo
    echo "compiled suite: $npass passed, $nfail failed, $nskip skipped"
    if [ "$nfail" -ne 0 ]; then
        for f in $failures; do echo "  $f"; done
        exit 1
    fi
    exit 0
fi

# ------------------------------------------------------------------ backend

for src in tests/backend/*.ll; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .ll)
    selected "$name" || continue
    stem="tests/backend/$name"
    exe="$TMP/backend-$name"

    if ! "$CC" -O2 -flto -Wno-override-module "$src" "$BUILD/l0rt.o" \
        "$BUILD/l0host.o" -o "$exe" 2> "$TMP/link.err"; then
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
#
# They link the compiler's source, which may use anything the seed can
# compile, so stage 0 cannot run them. The current compiler builds them
# instead. Their goldens were always the compiler's own output, since stage 0
# only ran the compiler's code, so --bless blesses them here as before, and
# --compiled runs them again through the bootstrapped compiler.
#
# Each builds the whole compiler, so they are built and run at once, each
# leaving its result under its own name, and judged in order afterward.

# stage_case NAME builds tests/compiler/NAME with the compiler $now and runs
# it, leaving its result in $TMP/compiler-NAME, or, if it could not be built,
# what failed in $TMP/compiler-NAME.what and why in $TMP/compiler-NAME.why.
stage_case() {
    s_stem="tests/compiler/$1"
    s_res="$TMP/compiler-$1"
    # shellcheck disable=SC2046
    if ! L0_COMPILER="$now" ./tools/l0c "$s_stem.l0" $(extra_sources "$s_stem") \
        > "$s_res.ll" 2> "$s_res.why"; then
        echo "the compiler rejected it" > "$s_res.what"
    elif ! link_quick "$s_res.ll" "$s_res.exe" 2> "$s_res.why"; then
        echo "generated IR did not assemble" > "$s_res.what"
    else
        exec_case "$s_res" "$s_stem" "$s_res.exe"
    fi
}

stage_names=""
for src in tests/compiler/*.l0; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .l0)
    case "$name" in
        fmt) continue ;; # shared helper, not a test
    esac
    selected "$name" || continue
    stage_names="$stage_names $name"
done
if [ -n "$stage_names" ]; then
    now=$(current_compiler) || exit 1
    for name in $stage_names; do
        stage_case "$name" &
    done
    wait
    for name in $stage_names; do
        res="$TMP/compiler-$name"
        if [ -f "$res.what" ]; then
            nfail=$((nfail + 1))
            failures="$failures compiler/$name"
            echo "FAIL compiler/$name: $(cat "$res.what")"
            sed 's/^/    /' "$res.why"
        else
            judge_case compiler "$name" "tests/compiler/$name" "$res"
        fi
    done
fi

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
nio=$(ls tests/io/*.l0 tests/unit/*_test.l0 2> /dev/null | wc -l | tr -d ' ')
[ "$nio" -gt 0 ] && echo "tests/io and tests/unit: $nio files stage 0 cannot run; tools/test.sh --compiled runs them"
if [ "$nfail" -eq 0 ]; then
    echo "all $npass tests passed"
    exit 0
fi
echo "$npass passed, $nfail failed:"
for f in $failures; do
    echo "  $f"
done
exit 1
