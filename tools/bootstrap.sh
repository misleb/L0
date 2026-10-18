#!/bin/sh
# Builds the L0 compiler from the L0 compiler and verifies self-compilation.
#
# Usage: tools/bootstrap.sh [--refresh-seed] [--virt]
#
#   --refresh-seed   after a successful fixpoint, install the result as
#                    bootstrap/stage2.ll. See "When to refresh the seed" below.
#   --virt           also take the last step on QEMU's virt board, with no
#                    operating system: stage2, built as a board image, must
#                    compile compiler.l0 to stage3.ll's bytes there too, and
#                    again built as a process, under the kernel in
#                    tests/virt/proc/harness and the one in L0 in
#                    tests/virt/user (spec sections 6.13 and 9.2), for each
#                    CPU with a virt board, or those L0_VIRT_ARCHS names.
#                    Needs qemu-system-aarch64 and qemu-system-riscv64, and
#                    Docker or L0_VIRT_LD.
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
VIRT=0
for arg in "$@"; do
    case "$arg" in
        --refresh-seed) REFRESH=1 ;;
        --virt) VIRT=1 ;;
        *)
            echo "usage: tools/bootstrap.sh [--refresh-seed] [--virt]" >&2
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

# -------------------------------------------- the last step, on the board

# stage2 again, for each CPU with a virt board, or those L0_VIRT_ARCHS
# names: as an image for QEMU's virt board, linked with the board's runtime
# as tools/build.sh left it in build/virt-ARCH, and booted on the same
# source. It must write stage3.ll exactly: the compiler compiles itself to
# itself with no operating system beneath it. Then, where the CPU has a
# process runtime and a harness kernel, as a process, under that kernel and
# under the one in L0.

# same_bytes WHERE TAGGED: whether stage2 wrote stage3.ll's bytes WHERE,
# into TAGGED, as the compiler tags its output.
same_bytes() {
    case "$(head -n 1 "$2")" in
        O) tail -n +2 "$2" > "${2%.tagged}" ;;
        *)
            echo "FAIL: stage2 $1 did not write IR" >&2
            head -5 "$2" | sed 's/^/    /' >&2
            exit 1
            ;;
    esac
    if ! cmp -s "$BUILD/stage3.ll" "${2%.tagged}"; then
        echo "FAIL: $1, stage2 compiles compiler.l0 to other bytes"
        echo "      than on this host. First difference:"
        diff "$BUILD/stage3.ll" "${2%.tagged}" | head -20 | sed 's/^/    /'
        exit 1
    fi
}

# virt_step ARCH takes the last step on ARCH's board, and as a process.
virt_step() {
    a=$1
    L0_ARCH=$a
    export L0_ARCH
    if [ ! -f "$BUILD/virt-$a/parts" ]; then
        echo "error: $CC cannot build the virt board's runtime for $a" >&2
        exit 1
    fi
    L0_RUNTIMES="$BUILD" tools/l0 link --target virt "$BUILD/stage2.ll" \
        -o "$BUILD/stage2-$a.img"
    start=$(date +%s)
    if ! tools/l0 boot "$BUILD/stage2-$a.img" < "$SRC" > "$BUILD/stage3-virt-$a.ll.tagged"; then
        echo "FAIL: stage2 failed on the $a virt board" >&2
        exit 1
    fi
    took=$(( $(date +%s) - start ))
    same_bytes "on the $a virt board" "$BUILD/stage3-virt-$a.ll.tagged"
    echo "ON THE BOARD: stage2 on QEMU's $a virt board writes stage3.ll too, in $took s"

    if [ ! -f "$BUILD/proc-$a/parts" ] || [ ! -f "tests/virt/proc/harness/$a/kernel.ll" ]; then
        echo "AS A PROCESS: not on $a, which has no process runtime or harness kernel yet"
        return 0
    fi

    # And as a process of a kernel: stage2 built with runtime/bare/proc.ll,
    # run at user level in an address space of its own by the harness
    # kernel, its input and output by system calls.
    L0_RUNTIMES="$BUILD" tools/l0 link --target proc "$BUILD/stage2.ll" \
        -o "$BUILD/stage2-proc-$a.img"
    start=$(date +%s)
    if ! tests/virt/proc/harness/boot.sh "$BUILD/proc-boot-$a" - "$BUILD/stage2-proc-$a.img" \
        < "$SRC" > "$BUILD/stage3-proc-$a.ll.tagged"; then
        echo "FAIL: stage2 failed as a process on $a" >&2
        exit 1
    fi
    took=$(( $(date +%s) - start ))
    same_bytes "as a process on $a" "$BUILD/stage3-proc-$a.ll.tagged"
    echo "AS A PROCESS: stage2 under the $a harness kernel writes stage3.ll too, in $took s"

    # And as the process of a kernel written in L0, tests/virt/user/kernel.l0
    # (spec section 6.13), built by stage2 itself.
    if ! L0_COMPILER="$BUILD/stage2" L0_RUNTIMES="$BUILD" tools/l0 build \
        --target virt tests/virt/user/kernel.l0 -o "$BUILD/user-kernel-$a.img"; then
        echo "FAIL: stage2 did not build tests/virt/user/kernel.l0 for $a" >&2
        exit 1
    fi
    start=$(date +%s)
    if ! tests/virt/user/run.sh "$BUILD/user-kernel-$a.img" "$BUILD/user-boot-$a" - \
        "$BUILD/stage2-proc-$a.img" < "$SRC" > "$BUILD/stage3-user-$a.ll.tagged"; then
        echo "FAIL: stage2 failed as a process of the L0 kernel on $a" >&2
        exit 1
    fi
    took=$(( $(date +%s) - start ))
    same_bytes "under the L0 kernel on $a" "$BUILD/stage3-user-$a.ll.tagged"
    echo "UNDER L0: stage2 as the process of a kernel in L0 on $a writes stage3.ll too, in $took s"
}

if [ "$VIRT" = 1 ]; then
    archs=${L0_VIRT_ARCHS:-}
    if [ -z "$archs" ]; then
        for m in runtime/targets/*.target; do
            T_KIND=""
            . "./$m"
            [ "$T_KIND" = board ] && archs="$archs $T_ARCH"
        done
    fi
    for a in $archs; do
        virt_step "$a"
    done
fi

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
