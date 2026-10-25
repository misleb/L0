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
#                  as processes of a kernel, through --target proc, once for
#                  each CPU with a board, aarch64 and riscv64, or those
#                  L0_VIRT_ARCHS names; needs qemu-system-aarch64 and
#                  qemu-system-riscv64, and Docker or L0_VIRT_LD
#   name-filter    a substring of a test's file name without its directory or
#                  extension, such as bundle_prelude, matched in every suite.
#                  A filter that matches nothing passes, with "0 tests".
#
#   L0_JOBS        how many of --compiled's or --virt's tests run at once,
#                  beside --virt's fixpoint on each board; by default,
#                  the host's CPUs, as getconf _NPROCESSORS_ONLN counts them,
#                  but at most one for each 2 GB of its memory
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
#   <stem>.refused tests/virt only: the board's toolchain must refuse to
#                  build the program, writing this file's text
#   <stem>.layout  tests/virt only: the options of its layout, --heap-mb,
#                  --stack-mb, or --layout and a path from the root, one per
#                  line, for a program built for the board alone, so it has
#                  a .board or .refused file too; <stem>.ARCH.layout first
#   <stem>.args    tests/virt: the program's arguments, one per line, which
#                  hold no spaces: its boot arguments on the board, and its
#                  arguments as a process under both kernels.
#                  tests/virt/proc: the process's arguments, which may
#                  hold spaces, so the L0 kernel does not run it.
#                  tests/virt/user: the L0 kernel's boot arguments
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

if [ "$COMPILED" = 1 ] || [ "$VIRT" = 1 ]; then
    # Their tests run L0_JOBS at once, by default one for each CPU the host
    # has, but at most one for each 2 GB of its memory, since a
    # tests/compiler job compiles a program the size of the compiler, which
    # takes over a gigabyte. Each leaves what it did under its own name and
    # reads nothing another writes. They are judged afterward, one at a time
    # in the order they were listed, so the report is the same however many
    # ran at once.
    njobs=${L0_JOBS:-$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 1)}
    case $njobs in
        '' | *[!0-9]*) njobs=0 ;;
    esac
    if [ "$njobs" -lt 1 ]; then
        echo "L0_JOBS must be a positive number, not '${L0_JOBS:-}'" >&2
        exit 2
    fi
    if [ -z "${L0_JOBS:-}" ]; then
        # The host's memory in megabytes: Linux's by getconf, macOS's,
        # which getconf does not give, by sysctl.
        mem_mb=""
        if pages=$(getconf _PHYS_PAGES 2> /dev/null) &&
            psize=$(getconf PAGESIZE 2> /dev/null); then
            mem_mb=$((pages / 1024 * psize / 1024))
        elif bytes=$(sysctl -n hw.memsize 2> /dev/null); then
            mem_mb=$((bytes / 1048576))
        fi
        if [ -n "$mem_mb" ] && [ "$njobs" -gt $((mem_mb / 2048)) ]; then
            njobs=$((mem_mb / 2048))
        fi
        [ "$njobs" -ge 1 ] || njobs=1
    fi
    # It is this script's: the l0 test of tests/unit's files, each one of
    # its jobs, runs a file's tests one at a time, l0 test's default on
    # this host, and is told to on the board.
    unset L0_JOBS
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

# run_case SUITE NAME STEM COMMAND... runs a test and judges it, with what
# it did in RUNRES, a job's own, if that is set.
run_case() {
    suite=$1
    name=$2
    stem=$3
    shift 3
    exec_case "${RUNRES:-$TMP/run}" "$stem" "$@"
    judge_case "$suite" "$name" "$stem" "${RUNRES:-$TMP/run}"
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

    out_file=$(expect_file "$stem" out)
    err_file=$(expect_file "$stem" err)
    exit_file=$(expect_file "$stem" exit)
    got_exit=$(cat "$res.exit")
    label="${VARCH:+$VARCH:}$suite/$name"

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
    failures="$failures $label"
    echo "FAIL $label: $why"
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

# VARCH is the CPU --virt is testing, and empty outside it. A test's
# expectation, or its arguments, for that CPU is <stem>.ARCH.EXT if there is
# one, and <stem>.EXT otherwise.
VARCH=""

expect_file() {
    if [ -n "$VARCH" ] && [ -f "$1.$VARCH.$2" ]; then
        echo "$1.$VARCH.$2"
    else
        echo "$1.$2"
    fi
}

# The arguments a tests/virt program is booted with, one per line of its
# .args file, which hold no spaces.
args_of() {
    a=$(expect_file "$1" args)
    if [ -f "$a" ]; then
        tr '\n' ' ' < "$a"
    fi
}

# The layout options a tests/virt program is built with, from its .layout
# file, a CPU's own first, which hold no spaces, with paths from the root.
layout_of() {
    l=$(expect_file "$1" layout)
    if [ -f "$l" ]; then
        tr '\n' ' ' < "$l"
    fi
}

# --------------------------------------------------------------------- virt
#
# For each CPU with a virt board, aarch64 and riscv64, or those
# L0_VIRT_ARCHS names: the fixpoint's last step on QEMU's virt board for
# it, and then the compiled suite's programs there, a host without an
# operating system (spec section 9.2), against the very expectations
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
# tests/virt programs, and tests/virt/unit's, are built with the board's
# constants, tests/virt/board/virt-ARCH.l0, beside them, and tests/virt/ARCH
# holds those that only one CPU's board runs. A test's expectations for one
# CPU, where they differ, are <stem>.ARCH.out and the like. A program with a
# <stem>.initrd is booted with those bytes as QEMU's -initrd, its standard
# input by the device tree. A CPU with no --target proc runtime, or no
# harness kernel, skips what runs as a process. The Raspberry Pi 5, which no
# emulator runs, is checked only to build, in tests/virt/pi5, and to be
# refused by l0 boot and written out by l0 card.
#
# Every image is linked by one container, started once and given each link
# by docker exec, rather than a docker run per image, unless L0_VIRT_LD
# already names a linker.

if [ "$VIRT" = 1 ]; then
    vstart=$(date +%s)
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
    L0_RUNTIMES="$BUILD"
    export L0_VIRT_LD L0_RUNTIMES
    nskip=0
    base_tmp=$TMP

    # The suite's cases run as jobs, njobs at once. A job is a function the
    # loops below hand to spawn, which runs it in a subshell of its own,
    # with the counts at 0 and what it writes, its FAIL lines among them,
    # in a file; it reads nothing another job writes. pool_judge then waits
    # for each job spawned since it last ran, in the order they were
    # spawned, writes what the job wrote, and adds its counts to the
    # suite's. So a case's report and its place in the report are what
    # they were when the cases ran one at a time.
    POOL="$base_tmp/pool"
    mkdir -p "$POOL"
    mkfifo "$POOL/slots"
    exec 3<> "$POOL/slots"
    rm -f "$POOL/slots"
    k=0
    while [ "$k" -lt "$njobs" ]; do
        echo >&3
        k=$((k + 1))
    done
    pool_k=0
    pool_judged=0

    # spawn [-free] FUNCTION ARG... runs FUNCTION ARG... as a job once one
    # of the pool's slots is free, or at once with -free, for a job that
    # runs beside the pool's, as a board's fixpoint does. It runs with -e
    # off, so a job ends by returning 0, and anything else is the suite's
    # own failure, which pool_judge stops the suite for.
    spawn() {
        pool_slot=1
        if [ "$1" = -free ]; then
            pool_slot=0
            shift
        fi
        [ "$pool_slot" = 0 ] || read -r _ <&3
        pool_k=$((pool_k + 1))
        pool_res="$POOL/$pool_k"
        {
            (
                npass=0 nfail=0 nskip=0 failures=""
                RUNRES="$pool_res.run"
                pool_st=0
                "$@" || pool_st=$?
                echo "$pool_st $npass $nfail $nskip" > "$pool_res.n"
                echo "$failures" > "$pool_res.f"
            ) > "$pool_res.out" 2>&1 || true
            [ "$pool_slot" = 0 ] || echo >&3
        } < /dev/null &
        eval "pool_pid_$pool_k=\$!"
    }

    pool_judge() {
        while [ "$pool_judged" -lt "$pool_k" ]; do
            pool_judged=$((pool_judged + 1))
            eval "pool_pid=\$pool_pid_$pool_judged"
            wait "$pool_pid" || true
            pool_res="$POOL/$pool_judged"
            [ -s "$pool_res.out" ] && cat "$pool_res.out"
            pool_st=""
            [ -f "$pool_res.n" ] && read -r pool_st pool_p pool_f pool_s < "$pool_res.n"
            if [ "$pool_st" != 0 ]; then
                echo "error: a job of the suite stopped part way (${pool_st:-killed})" >&2
                exit 1
            fi
            pool_fl=""
            read -r pool_fl < "$pool_res.f" || true
            npass=$((npass + pool_p))
            nfail=$((nfail + pool_f))
            nskip=$((nskip + pool_s))
            failures="$failures $pool_fl"
        done
    }

    # The CPUs with a board QEMU emulates: every such board manifest's,
    # unless L0_VIRT_ARCHS names some. A board with no emulator, the
    # Raspberry Pi 5, adds none; tests/virt/pi5 checks what is left of it.
    varchs=${L0_VIRT_ARCHS:-}
    if [ -z "$varchs" ]; then
        for m in runtime/targets/*.target; do
            T_KIND="" T_QEMU=""
            . "$m"
            [ "$T_KIND" = board ] && [ -n "$T_QEMU" ] && varchs="$varchs $T_ARCH"
        done
    fi

    # The extra sources of a tests/virt program, NAME.extra's and the
    # board's constants.
    virt_extra() {
        echo "$(extra_sources "$1") tests/virt/board/virt-$VARCH.l0"
    }

    # virt_arch ARCH runs the suite on ARCH's board.
    virt_arch() {
    VARCH=$1
    L0_ARCH=$1
    export L0_ARCH
    TMP="$base_tmp/$1"
    mkdir -p "$TMP"
    vdir="$BUILD/virt-$VARCH"
    pdir="$BUILD/proc-$VARCH"
    if [ ! -f "$vdir/parts" ]; then
        nfail=$((nfail + 1))
        failures="$failures $VARCH:virt/runtime"
        echo "FAIL $VARCH:virt/runtime: $CC cannot build the runtime for --target virt --arch $VARCH"
        [ -f "$vdir.err" ] && sed 's/^/    /' "$vdir.err"
        return 0
    fi
    # Whether this CPU's programs run as processes too: under the harness
    # kernel in IR, and under the L0 kernel.
    procs=0
    if [ -f "$pdir/parts" ] && [ -f "tests/virt/proc/harness/$VARCH/kernel.ll" ]; then
        procs=1
    fi

    # First the goal's measure: the compiler compiles itself on the board,
    # and as a process, to the bytes it writes here (tools/bootstrap.sh
    # --virt). It runs beside this CPU's cases, which build with the
    # current compiler, not the stages it writes in build/, and is done
    # before the next CPU's starts, which writes them again.
    virt_fixpoint() {
        if L0_VIRT_ARCHS=$VARCH ./tools/bootstrap.sh --virt > "$TMP/bootstrap.log" 2>&1; then
            npass=$((npass + 1))
        else
            nfail=$((nfail + 1))
            failures="$failures $VARCH:virt/fixpoint"
            echo "FAIL $VARCH:virt/fixpoint: tools/bootstrap.sh --virt failed"
            sed 's/^/    /' "$TMP/bootstrap.log"
        fi
    }
    spawn -free virt_fixpoint

    # virt_case SUITE NAME SRC STEM builds SRC for the board and judges it,
    # in files named for the suite too, since tests/io and tests/virt share
    # names.
    virt_case() {
        vsuite=$1
        vname_=$2
        vsrc=$3
        vstem=$4
        vres="$TMP/$vsuite-$vname_"
        # shellcheck disable=SC2046
        if ! ./tools/l0c "$vsrc" $(extra_sources "$vstem") > "$vres.ll" \
            2> "$vres.cerr"; then
            nfail=$((nfail + 1))
            failures="$failures $VARCH:$vsuite/$vname_"
            echo "FAIL $VARCH:$vsuite/$vname_: compiler rejected a valid program"
            sed 's/^/    /' "$vres.cerr"
            return 0
        fi
        if ! ./tools/l0 link --target virt "$vres.ll" -o "$vres.img" \
            > "$vres.lerr" 2>&1; then
            nfail=$((nfail + 1))
            failures="$failures $VARCH:$vsuite/$vname_"
            echo "FAIL $VARCH:$vsuite/$vname_: did not link for the board"
            sed 's/^/    /' "$vres.lerr"
            return 0
        fi
        run_case "$vsuite" "$vname_" "$vstem" ./tools/l0 boot "$vres.img"
        return 0
    }

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
        spawn virt_case "virt-$(basename "$dir")" "$name" "$src" "$stem"
    done

    # virt_unit NAME SRC USTEM runs the tests of SRC, written with l0 test,
    # on the board with l0 test --target virt, in a scratch directory as
    # --compiled runs them, and one at a time, since this is one job of
    # the pool already.
    virt_unit() {
        udir="$TMP/vunit-$1"
        mkdir -p "$udir"
        case $2 in
            tests/virt/*) uextra=$(virt_extra "$ROOT/$3") ;;
            *) uextra=$(extra_sources "$ROOT/$3") ;;
        esac
        # shellcheck disable=SC2046
        if (cd "$udir" && L0_COMPILER="$vcc" L0_JOBS=1 "$ROOT/tools/l0" test \
            --target virt "$ROOT/$2" $(echo "$uextra" | sed "s|[^ ][^ ]*|$ROOT/&|g")) \
            > "$udir.tap" 2>&1; then
            npass=$((npass + 1))
        else
            nfail=$((nfail + 1))
            failures="$failures $VARCH:virt-unit/$1"
            echo "FAIL $VARCH:virt-unit/$1:"
            grep -v '^ok ' "$udir.tap" | sed 's/^/    /'
        fi
        return 0
    }
    # tests/unit's files but for those with a .host file, and
    # tests/virt/unit's, the board's own.
    for src in tests/unit/*_test.l0 tests/virt/unit/*_test.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        ustem="${src%.l0}"
        if [ -f "$ustem.host" ]; then
            nskip=$((nskip + 1))
            continue
        fi
        spawn virt_unit "$name" "$src" "$ustem"
    done

    # virt_program NAME SRC STEM builds tests/virt's SRC for the board and
    # judges it, or judges how the board's toolchain refuses it.
    virt_program() {
        name=$1
        src=$2
        stem=$3
        if [ -f "$stem.refused" ]; then
            # A program the board's toolchain must refuse to build, saying
            # what its .refused file says.
            # shellcheck disable=SC2046
            if L0_COMPILER="$vcc" ./tools/l0 build --target virt $(layout_of "$stem") \
                "$src" $(virt_extra "$stem") -o "$TMP/$name.img" > "$TMP/$name.berr" 2>&1; then
                nfail=$((nfail + 1))
                failures="$failures $VARCH:virt/$name"
                echo "FAIL $VARCH:virt/$name: built, though it must be refused"
            elif ! { uniq "$stem.refused" > "$TMP/$name.want" &&
                     uniq "$TMP/$name.berr" > "$TMP/$name.got" &&
                     cmp -s "$TMP/$name.got" "$TMP/$name.want"; }; then
                # Compared with a line the linker repeats written once: some
                # versions of ld.lld say an error twice, and the wording is
                # what the file pins down.
                nfail=$((nfail + 1))
                failures="$failures $VARCH:virt/$name"
                echo "FAIL $VARCH:virt/$name: refused, but not as $stem.refused says"
                diff -u "$TMP/$name.want" "$TMP/$name.got" | sed 's/^/    /' || true
            else
                npass=$((npass + 1))
            fi
            return 0
        fi
        # shellcheck disable=SC2046
        if ! L0_COMPILER="$vcc" ./tools/l0 build --target virt $(layout_of "$stem") \
            "$src" $(virt_extra "$stem") -o "$TMP/$name.img" \
            > "$TMP/$name.berr" 2>&1; then
            nfail=$((nfail + 1))
            failures="$failures $VARCH:virt/$name"
            echo "FAIL $VARCH:virt/$name: did not build"
            sed 's/^/    /' "$TMP/$name.berr"
            return 0
        fi
        # A program with a <stem>.initrd is given those bytes as the
        # firmware's initrd, QEMU's -initrd, which is standard input where
        # the device tree says so (spec section 10.3). One with a
        # <stem>.qemu is booted with the devices its QEMU arguments add,
        # such as PCIe functions.
        initrd=""
        [ -f "$stem.initrd" ] && initrd="-initrd $stem.initrd"
        [ -f "$stem.qemu" ] && initrd="$initrd $(cat "$stem.qemu")"
        # shellcheck disable=SC2046
        run_case virt "$name" "$stem" env L0_QEMU_ARGS="$initrd" \
            ./tools/l0 boot "$TMP/$name.img" $(args_of "$stem")
        return 0
    }
    for src in tests/virt/*.l0 tests/virt/"$VARCH"/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        spawn virt_program "$name" "$src" "${src%.l0}"
    done

    # The same programs, but for those a .board file keeps on the board, as
    # processes of a kernel (spec section 9.2), each
    # built with tools/l0 build --target proc and run alone, as the first
    # process of tests/virt/proc/harness/kernel.ll, against the board's
    # expectations: that kernel gives no files or environment, which is
    # what the board gives, the arguments the program's .args file gives,
    # as the board does, and maps the board's devices. Then
    # tests/virt/proc, the process host's own, with the arguments and the
    # processes beside it that its .args and .with files give.
    pwork="$TMP/proc"
    harness=tests/virt/proc/harness

    # elf_word FILE OFF LEN: the LEN-byte number at OFF in FILE, read in
    # the host's order, which on every host here is little endian, as the
    # ELF is.
    elf_word() {
        od -An -tu"$3" -j "$2" -N "$3" "$1" | tr -d ' '
    }

    # elf_ok IMG: whether IMG is a process's image as spec section 10.3
    # lists it, for this CPU, saying why not if it is not: an ELF64 ET_EXEC
    # for the machine, entered at 0xC0000000, whose PT_LOADs, page-aligned,
    # are the code, the rodata, and the data, in that order, the last two
    # each left out when empty, so none is writable and executable.
    elf_ok() {
        mach=183                                    # EM_AARCH64
        [ "$VARCH" = riscv64 ] && mach=243          # EM_RISCV
        if [ "$(od -An -tx1 -N 4 "$1" | tr -d ' ')" != 7f454c46 ]; then
            echo "not an ELF"
            return 1
        fi
        [ "$(elf_word "$1" 4 2)" = 258 ] || { echo "not ELFCLASS64 and little endian"; return 1; }
        [ "$(elf_word "$1" 16 2)" = 2 ] || { echo "not ET_EXEC"; return 1; }
        [ "$(elf_word "$1" 18 2)" = "$mach" ] || { echo "e_machine is not $mach"; return 1; }
        [ "$(elf_word "$1" 24 8)" = 3221225472 ] || { echo "e_entry is not 0xC0000000"; return 1; }
        [ "$(elf_word "$1" 54 2)" = 56 ] || { echo "e_phentsize is not 56"; return 1; }
        phoff=$(elf_word "$1" 32 8)
        phnum=$(elf_word "$1" 56 2)
        flags=""
        k=0
        while [ "$k" -lt "$phnum" ]; do
            ph=$((phoff + k * 56))
            if [ "$(elf_word "$1" "$ph" 4)" = 1 ]; then         # PT_LOAD
                off=$(elf_word "$1" $((ph + 8)) 8)
                va=$(elf_word "$1" $((ph + 16)) 8)
                if [ $((off % 4096)) != 0 ] || [ $((va % 4096)) != 0 ] ||
                    [ "$(elf_word "$1" $((ph + 48)) 8)" != 4096 ]; then
                    echo "program header $k is not page-aligned"
                    return 1
                fi
                flags="$flags$(elf_word "$1" $((ph + 4)) 4)"
            fi
            k=$((k + 1))
        done
        case $flags in
            5 | 54 | 56 | 546) ;;      # PF_R|PF_X, then PF_R, then PF_R|PF_W
            *)
                echo "its PT_LOADs' flags are $flags, not 5, 4, and 6 in order"
                return 1
                ;;
        esac
    }

    # proc_build SUITE NAME SRC STEM [IMG] builds SRC as a process image,
    # IMG or else $TMP/NAME.proc.img, or fails the test, as it does if the
    # image is not section 10.3's. A job that builds a program another job
    # runs names an IMG of its own.
    proc_build() {
        pimg=${5:-$TMP/$2.proc.img}
        # shellcheck disable=SC2046
        if ! L0_COMPILER="$vcc" ./tools/l0 build --target proc "$3" \
            $(virt_extra "$4") -o "$pimg" > "$pimg.berr" 2>&1; then
            nfail=$((nfail + 1))
            failures="$failures $VARCH:$1/$2"
            echo "FAIL $VARCH:$1/$2: did not build as a process"
            sed 's/^/    /' "$pimg.berr"
            return 1
        fi
        if ! why=$(elf_ok "$pimg"); then
            nfail=$((nfail + 1))
            failures="$failures $VARCH:$1/$2"
            echo "FAIL $VARCH:$1/$2: its process image is not spec section 10.3's: $why"
            return 1
        fi
    }

    if [ "$procs" = 0 ]; then
        virt_noprocs() {
            nskip=$((nskip + 1))
            echo "skip $VARCH: no process runtime or harness kernel, so nothing runs as a process"
            return 0
        }
        spawn virt_noprocs
        pool_judge
        return 0
    fi

    # The harness kernel, linked into $pwork once, before any job boots it
    # there; each boot then leaves its own input beside it.
    "$harness/boot.sh" "$pwork" > "$TMP/proc-link.log" 2>&1 || true

    # proc_program NAME SRC STEM builds tests/virt's SRC as a process and
    # runs it under the harness kernel.
    proc_program() {
        proc_build virt-proc "$1" "$2" "$3" || return 0
        pargs=$(expect_file "$3" args)
        [ -f "$pargs" ] || pargs=-
        run_case virt-proc "$1" "$3" "$harness/boot.sh" "$pwork" "$pargs" \
            "$TMP/$1.proc.img"
        return 0
    }
    for src in tests/virt/*.l0 tests/virt/"$VARCH"/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="${src%.l0}"
        [ -f "$stem.board" ] && continue
        [ -f "$stem.refused" ] && continue
        spawn proc_program "$name" "$src" "$stem"
    done

    # proc_suite NAME SRC STEM builds tests/virt/proc's SRC and runs it
    # under the harness kernel, beside what its .with file names: spin,
    # built for it alone, or the harness's own IR, such as fault.
    proc_suite() {
        proc_build proc "$1" "$2" "$3" || return 0
        args=-
        [ -f "$3.args" ] && args="$3.args"
        beside=""
        if [ -f "$3.with" ]; then
            for w in $(cat "$3.with"); do
                case $w in
                    spin)
                        proc_build proc spin "$harness/spin.l0" "$harness/spin" \
                            "$TMP/spin-$1.proc.img" || return 0
                        beside="$beside $TMP/spin-$1.proc.img"
                        ;;
                    *) beside="$beside $w" ;;
                esac
            done
        fi
        # shellcheck disable=SC2086
        run_case proc "$1" "$3" "$harness/boot.sh" "$pwork" "$args" \
            "$TMP/$1.proc.img" $beside
        return 0
    }
    for src in tests/virt/proc/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        spawn proc_suite "$name" "$src" "tests/virt/proc/$name"
    done

    # And under a kernel written in L0 (spec sections 6.13 and 6.14): each
    # tests/virt program, as built above, the one process of
    # tests/virt/user/kernel.l0, against the board's expectations once more;
    # then tests/virt/user's own, each a NAME.procs file naming its
    # processes in order, an L0 program by its path or the harness's IR by
    # its name, such as fault, which the kernel must kill, or by
    # foreign:NAME, another CPU's, which it must not start; then
    # tests/virt/proc's, beside what their .with files name, as under the
    # harness, but for those given arguments, which this kernel gives none.
    user=tests/virt/user
    uwork="$TMP/user"
    mkdir -p "$uwork"

    # user_img NAME: where user_ir links NAME.
    user_img() {
        case $1 in
            foreign:*) echo "$uwork/foreign-${1#foreign:}.img" ;;
            *) echo "$uwork/$1.img" ;;
        esac
    }

    # user_ir NAME links this CPU's harness's NAME.ll as a process, into
    # $uwork/NAME.img, or fails the test of that name. NAME may be
    # foreign:NAME, for the NAME.ll of another CPU's harness, built for
    # that CPU, into $uwork/foreign-NAME.img, which a kernel here must not
    # start.
    user_ir() {
        img=$(user_img "$1")
        case $1 in
            foreign:*)
                irname=${1#foreign:}
                irarch=""
                for m in runtime/targets/proc-*.target; do
                    T_ARCH=""
                    . "$m"
                    if [ "$T_ARCH" != "$VARCH" ] && [ -f "$harness/$T_ARCH/$irname.ll" ]; then
                        irarch=$T_ARCH
                        break
                    fi
                done
                if [ -z "$irarch" ]; then
                    nfail=$((nfail + 1))
                    failures="$failures $VARCH:user/$1"
                    echo "FAIL $VARCH:user/$1: no other CPU's harness has $irname.ll"
                    return 1
                fi
                ;;
            *)
                irname=$1
                irarch=$VARCH
                ;;
        esac
        if [ -f "$img" ]; then
            return 0
        fi
        T_CFLAGS="" T_LDFLAGS=""
        . "runtime/targets/proc-$irarch.target"
        # shellcheck disable=SC2086
        if { "$CC" --target="$T_TRIPLE" $T_CFLAGS -O2 -c "$harness/$irarch/$irname.ll" \
                -o "$img.o" &&
            "$L0_VIRT_LD" -T runtime/proc.ld $T_LDFLAGS "$img.o" -o "$img"; } \
            > "$img.berr" 2>&1; then
            if [ "$irarch" != "$VARCH" ] || why=$(elf_ok "$img"); then
                return 0
            fi
            nfail=$((nfail + 1))
            failures="$failures $VARCH:user/$1"
            echo "FAIL $VARCH:user/$1: its process image is not spec section 10.3's: $why"
            rm -f "$img"
            return 1
        fi
        nfail=$((nfail + 1))
        failures="$failures $VARCH:user/$1"
        echo "FAIL $VARCH:user/$1: did not build"
        sed 's/^/    /' "$img.berr"
        rm -f "$img"
        return 1
    }
    # user_prepare builds kernel.l0 for the board, and links the harness IR
    # that tests/virt/user's .procs files and tests/virt/proc's .with files
    # name, each once, before the jobs that boot them start. One that does
    # not link is left for the test that uses it to fail on.
    user_prepare() {
        if L0_COMPILER="$vcc" ./tools/l0 build --target virt "$user/kernel.l0" \
            -o "$uwork/kernel.img" > "$uwork/kernel.berr" 2>&1; then
            : > "$uwork/kernel.ok"
        else
            nfail=$((nfail + 1))
            failures="$failures $VARCH:virt-user/kernel"
            echo "FAIL $VARCH:virt-user/kernel: did not build"
            sed 's/^/    /' "$uwork/kernel.berr"
        fi
        for w in $(cat "$user"/*.procs tests/virt/proc/*.with 2> /dev/null); do
            case $w in
                *.l0 | spin) ;;
                *) (user_ir "$w") > /dev/null 2>&1 || true ;;
            esac
        done
        return 0
    }
    spawn user_prepare
    # The process images the jobs so far built are what the L0 kernel's
    # jobs boot, so they are all done first.
    pool_judge
    [ -f "$uwork/kernel.ok" ] || return 0

    # user_program NAME STEM runs tests/virt's program as built above, the
    # one process of kernel.l0, whose arguments for process 0 are the
    # program's.
    user_program() {
        kargs=-
        pargs=$(expect_file "$2" args)
        if [ -f "$pargs" ]; then
            sed 's/^/0:/' "$pargs" > "$uwork/$1.kargs"
            kargs="$uwork/$1.kargs"
        fi
        run_case virt-user "$1" "$2" "$user/run.sh" \
            "$uwork/kernel.img" "$uwork" "$kargs" "$TMP/$1.proc.img"
        return 0
    }
    for src in tests/virt/*.l0 tests/virt/"$VARCH"/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        [ -f "$TMP/$name.proc.img" ] || continue
        spawn user_program "$name" "${src%.l0}"
    done

    # user_procs NAME SPEC runs the processes SPEC names under kernel.l0,
    # each L0 program among them built for this job alone, since another
    # job may run the same program.
    user_procs() {
        images=""
        for p in $(cat "$2"); do
            case $p in
                *.l0)
                    pn=$(basename "$p" .l0)
                    proc_build user "$pn" "$p" "${p%.l0}" "$uwork/$1-$pn.proc.img" ||
                        return 0
                    images="$images $uwork/$1-$pn.proc.img"
                    ;;
                *)
                    user_ir "$p" || return 0
                    images="$images $(user_img "$p")"
                    ;;
            esac
        done
        kargs=$(expect_file "$user/$1" args)
        [ -f "$kargs" ] || kargs=-
        # shellcheck disable=SC2086
        run_case user "$1" "$user/$1" "$user/run.sh" \
            "$uwork/kernel.img" "$uwork" "$kargs" $images
        return 0
    }
    for spec in "$user"/*.procs; do
        [ -f "$spec" ] || continue
        name=$(basename "$spec" .procs)
        selected "$name" || continue
        spawn user_procs "$name" "$spec"
    done

    # user_proc NAME STEM runs tests/virt/proc's program, as built above,
    # under kernel.l0, beside what its .with file names.
    user_proc() {
        beside=""
        if [ -f "$2.with" ]; then
            for w in $(cat "$2.with"); do
                case $w in
                    spin) beside="$beside $TMP/spin-$1.proc.img" ;;
                    *)
                        user_ir "$w" || return 0
                        beside="$beside $(user_img "$w")"
                        ;;
                esac
            done
        fi
        # shellcheck disable=SC2086
        run_case user-proc "$1" "$2" "$user/run.sh" \
            "$uwork/kernel.img" "$uwork" - "$TMP/$1.proc.img" $beside
        return 0
    }
    for src in tests/virt/proc/*.l0; do
        [ -f "$src" ] || continue
        name=$(basename "$src" .l0)
        selected "$name" || continue
        stem="tests/virt/proc/$name"
        [ -f "$stem.args" ] && continue
        [ -f "$TMP/$name.proc.img" ] || continue
        spawn user_proc "$name" "$stem"
    done
    pool_judge
    }

    for a in $varchs; do
        virt_arch "$a"
    done
    VARCH=""
    TMP=$base_tmp

    # The Raspberry Pi 5 has no emulator, so nothing of it runs here. What
    # can be checked is that each program of tests/virt/pi5 builds for it
    # with tools/l0 build --target pi5; that its image's header says the
    # board it is for, "pi5" at byte 48 and "ARM\x64" at 56, so that l0 boot
    # refuses it rather than start it on QEMU's board; and that l0 card
    # writes the files its SD card needs, arguments and input among them.
    # The programs' expectations, <stem>.out, are what a board's serial line
    # should show, for whoever runs one.
    pi5_check() {
        L0_ARCH=aarch64
        export L0_ARCH
        nin="$TMP/pi5.in"
        printf 'pi5 input\n' > "$nin"
        for src in tests/virt/pi5/*.l0; do
            [ -f "$src" ] || continue
            name=$(basename "$src" .l0)
            selected "$name" || continue
            img="$TMP/pi5-$name.img"
            why=""
            if ! L0_COMPILER="$vcc" ./tools/l0 build --target pi5 "$src" \
                -o "$img" > "$TMP/pi5-$name.berr" 2>&1; then
                why="did not build"
            elif [ "$(od -An -tx1 -j48 -N3 "$img" | tr -d ' \n')" != 706935 ] ||
                [ "$(od -An -tx1 -j56 -N4 "$img" | tr -d ' \n')" != 41524d64 ]; then
                why="its header does not name the Raspberry Pi 5"
            elif ./tools/l0 boot "$img" < /dev/null > /dev/null 2> "$TMP/pi5-$name.boot"; then
                why="l0 boot started it, though no emulator runs it"
            elif ! grep -q "no emulator" "$TMP/pi5-$name.boot"; then
                why="l0 boot refused it, but not for having no emulator"
            elif ! ./tools/l0 card "$img" "$TMP/pi5-$name.card" one two:2 \
                < "$nin" > /dev/null 2>&1 && [ ! -f "$TMP/pi5-$name.card/config.txt" ]; then
                why="l0 card wrote nothing"
            elif [ "$(head -n 1 "$TMP/pi5-$name.card/config.txt")" != "# written by l0 card" ] ||
                ! grep -qx "kernel=l0.img" "$TMP/pi5-$name.card/config.txt" ||
                ! grep -qx "pciex4_reset=0" "$TMP/pi5-$name.card/config.txt" ||
                ! grep -qx "hdmi_force_hotplug=1" "$TMP/pi5-$name.card/config.txt" ||
                ! grep -qx "initramfs input.bin 0x10000000" "$TMP/pi5-$name.card/config.txt"; then
                why="l0 card's config.txt is wrong"
            elif [ "$(cat "$TMP/pi5-$name.card/cmdline.txt")" != "--l0-args one two:2" ] ||
                ! cmp -s "$TMP/pi5-$name.card/input.bin" "$nin" ||
                ! cmp -s "$TMP/pi5-$name.card/l0.img" "$img"; then
                why="l0 card's files are wrong"
            elif ! ./tools/l0 card "$img" "$TMP/pi5-$name.card0" < /dev/null > /dev/null 2>&1 ||
                [ "$(cat "$TMP/pi5-$name.card0/cmdline.txt")" != "--l0-args" ] ||
                [ -f "$TMP/pi5-$name.card0/input.bin" ] ||
                grep -q initramfs "$TMP/pi5-$name.card0/config.txt"; then
                why="l0 card gave input where there is none"
            elif ./tools/l0 card "$img" "$TMP/pi5-$name.card1" "a b" < /dev/null > /dev/null 2>&1; then
                why="l0 card took an argument with a space"
            fi
            if [ -z "$why" ]; then
                npass=$((npass + 1))
            else
                nfail=$((nfail + 1))
                failures="$failures pi5/$name"
                echo "FAIL pi5/$name: $why"
                [ -f "$TMP/pi5-$name.berr" ] && sed 's/^/    /' "$TMP/pi5-$name.berr"
            fi
        done
    }
    pi5_check

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

    # compiled_build RES SRC STEM compiles SRC and links it into RES.exe;
    # or leaves RES.skip, if this compiler cannot compile it yet; or what
    # failed in RES.what, and why in RES.why.
    compiled_build() {
        # shellcheck disable=SC2046
        if ! ./tools/l0c "$2" $(extra_sources "$3") > "$1.ll" 2> "$1.why"; then
            if grep -q "not supported by this compiler yet" "$1.why"; then
                : > "$1.skip"
            else
                echo "compiler rejected a valid program" > "$1.what"
            fi
            return 1
        fi
        if ! ./tools/l0ll "$1.ll" "$1.exe" 2> "$1.why"; then
            echo "generated IR did not assemble" > "$1.what"
            return 1
        fi
    }

    # compiled_names SRC sets suite, name, stem, and res for the test SRC.
    compiled_names() {
        dir=${1%/*}
        suite=${dir#tests/}
        name=${1##*/}
        name=${name%.l0}
        stem="$dir/$name"
        res="$TMP/$suite-$name"
    }

    # compiled_run SRC builds and runs the test SRC, leaving what it did
    # beside $TMP/SUITE-NAME for compiled_judge. It counts nothing, since
    # it runs in a job of its own.
    compiled_run() {
        compiled_names "$1"
        st=0
        case $suite in
            check)
                # Programs that must be REJECTED.
                if ./tools/l0c "$1" > /dev/null 2> "$res.cerr"; then
                    : > "$res.accepted"
                fi
                ;;
            unit)
                # Tests written with l0 test, each file run in a scratch
                # directory so the files its tests write stay out of the
                # repository, and against the compiler and runtime just
                # built rather than the installed ones.
                mkdir -p "$res"
                # shellcheck disable=SC2046
                (cd "$res" && L0_COMPILER="$BUILD/l0c-native" \
                    L0_RUNTIME="$BUILD/l0rt.o" L0_HOST="$BUILD/l0host.o" \
                    "$ROOT/tools/l0" test "$ROOT/$1" \
                    $(extra_sources "$ROOT/$stem" | sed "s|[^ ][^ ]*|$ROOT/&|g")) \
                    > "$res.tap" 2>&1 || st=$?
                echo "$st" > "$res.status"
                ;;
            *)
                compiled_build "$res" "$1" "$stem" || return 0
                if [ "$suite" = io ] && [ -f "$stem.sh" ]; then
                    sh "$stem.sh" "$res.exe" "$res.ll" > "$res.shout" 2>&1 || st=$?
                    echo "$st" > "$res.status"
                else
                    exec_case "$res" "$stem" "$res.exe"
                fi
                ;;
        esac
    }

    # compiled_judge SRC judges what compiled_run left for SRC, and counts
    # it:
    #   tests/lang      against the interpreter's expectations, which is
    #                   what makes this differential rather than
    #                   self-referential
    #   tests/compiler  against the very same goldens the interpreted run
    #                   uses; these are pure functions of stdin, so any
    #                   difference at all means the two implementations
    #                   disagree
    #   tests/check     the compiler's wording differs from the
    #                   interpreter's, so these have their own .cerr
    #                   expectations; what matters is that every program the
    #                   interpreter rejects, the compiler rejects too
    #   tests/io        programs stage 0 cannot run, against hand-written
    #                   expectations, or by a script when what matters is
    #                   when output appears
    #   tests/unit      by l0 test's exit status
    compiled_judge() {
        compiled_names "$1"
        case $suite in
            lang | compiler) label="compiled/$name" ;;
            check) label="compiled-check/$name" ;;
            *) label="$suite/$name" ;;
        esac
        if [ -f "$res.skip" ]; then
            nskip=$((nskip + 1))
        elif [ -f "$res.what" ]; then
            nfail=$((nfail + 1))
            failures="$failures $label"
            echo "FAIL $label: $(cat "$res.what")"
            sed 's/^/    /' "$res.why"
        elif [ "$suite" = check ]; then
            cerr="$stem.cerr"
            if [ -f "$res.accepted" ]; then
                nfail=$((nfail + 1))
                failures="$failures $label"
                echo "FAIL $label: compiler ACCEPTED a program the interpreter rejects"
            elif [ "$BLESS_CHECK" = 1 ]; then
                cp "$res.cerr" "$cerr"
                echo "bless $label"
                npass=$((npass + 1))
            elif [ ! -f "$cerr" ]; then
                nfail=$((nfail + 1))
                failures="$failures $label"
                echo "FAIL $label: no expectation file"
            elif ! cmp -s "$res.cerr" "$cerr"; then
                nfail=$((nfail + 1))
                failures="$failures $label"
                echo "FAIL $label: diagnostics differ"
                diff -u "$cerr" "$res.cerr" | sed 's/^/    /' || true
            else
                npass=$((npass + 1))
            fi
        elif [ -f "$res.status" ]; then
            if [ "$(cat "$res.status")" = 0 ]; then
                npass=$((npass + 1))
            else
                nfail=$((nfail + 1))
                failures="$failures $label"
                if [ "$suite" = unit ]; then
                    echo "FAIL $label:"
                    grep -v '^ok ' "$res.tap" | sed 's/^/    /'
                else
                    echo "FAIL $label: $stem.sh failed"
                    sed 's/^/    /' "$res.shout"
                fi
            fi
        else
            judge_case "${label%%/*}" "$name" "$stem" "$res"
        fi
    }

    list="$TMP/compiled.list"
    : > "$list"
    for src in tests/lang/*.l0 tests/compiler/*.l0 tests/check/*.l0 \
        tests/io/*.l0 tests/unit/*_test.l0; do
        [ -f "$src" ] || continue
        case "$src" in tests/compiler/fmt.l0) continue ;; esac
        compiled_names "$src"
        selected "$name" || continue
        echo "$src" >> "$list"
    done

    # The pool is a pipe holding a line for each job that may start, opened
    # both ways so it never ends: a job starts once it has read a line, and
    # writes it back when it is done. Each job's standard input is
    # /dev/null, not the list being read.
    mkfifo "$TMP/pool"
    exec 3<> "$TMP/pool"
    rm -f "$TMP/pool"
    k=0
    while [ "$k" -lt "$njobs" ]; do
        echo >&3
        k=$((k + 1))
    done
    while read -r src; do
        read -r _ <&3
        { compiled_run "$src" || true; echo >&3; } < /dev/null &
    done < "$list"
    wait
    exec 3>&-

    while read -r src; do
        compiled_judge "$src"
    done < "$list"

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
