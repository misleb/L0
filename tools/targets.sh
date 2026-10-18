# The targets without libc, as runtime/targets/NAME.target describes each.
# Sourced, not executed, by tools/build.sh, tools/install.sh, and, in a
# source checkout, tools/l0. ROOT and CC must already be set.
#
# A target is a board, which an image boots on with no operating system
# beneath it, or a process of a kernel. Its manifest sets:
#   T_KIND          board or proc
#   T_ARCH          the CPU, as --arch names it: aarch64 or riscv64
#   T_TRIPLE        clang's --target for it
#   T_CFLAGS        what else clang needs for it, for every part and the
#                   program alike
#   T_PARTS         the host's parts, under runtime/, linked into every
#                   program beside runtime/l0rt.ll and runtime/freestanding.ll
#   T_LAYOUT        its linker script, under runtime/
#   T_TAIL_WORDS    if set, the most words a tail call may pass: the
#                   registers the fast calling convention has, where LLVM
#                   gets a tail call's words on the stack wrong (spec
#                   section 10.3), so a program with a wider one is refused
# and a board QEMU emulates, for l0 boot:
#   T_MAGIC         the four bytes at 0x38 of its images, in hex, which its
#                   boot protocol's header puts there and l0 boot reads
#   T_QEMU          the emulator, and T_QEMU_ARGS its machine
#   T_SERIAL        how the serial line reaches standard output: stdio, or
#                   fd3, a descriptor of its own, when firmware writes on
#                   QEMU's standard output, which is then thrown away
#   T_INPUT_LEN_AT  where standard input's length is loaded, a word, and
#   T_INPUT_AT      its bytes, at most T_INPUT_MAX of them
#
# A target's runtime is a directory of its own: each part as bitcode for
# T_TRIPLE, listed in order in its file parts, the layout as layout.ld, the
# manifest as target, and the Dockerfile of the container that links it.

# target_names: every target there is a manifest for.
target_names() {
    for _m in "$ROOT"/runtime/targets/*.target; do
        [ -f "$_m" ] && basename "$_m" .target
    done
}

# target_stale NAME DIR: whether DIR, NAME's runtime, is missing or older
# than anything it is built from.
target_stale() {
    _m="$ROOT/runtime/targets/$1.target"
    [ -f "$2/parts" ] || return 0
    T_PARTS="" T_LAYOUT=""
    # shellcheck source=/dev/null
    . "$_m"
    for _f in "$_m" "$ROOT/runtime/l0rt.ll" "$ROOT/runtime/freestanding.ll" \
        "$ROOT/runtime/$T_LAYOUT" "$ROOT/tools/virt/Dockerfile"; do
        [ "$_f" -nt "$2/parts" ] && return 0
    done
    for _p in $T_PARTS; do
        [ "$ROOT/runtime/$_p" -nt "$2/parts" ] && return 0
    done
    return 1
}

# target_runtime NAME DIR: builds NAME's runtime into DIR, or fails, leaving
# no DIR and clang's complaint in DIR.err, as when clang cannot target its
# CPU.
target_runtime() {
    _m="$ROOT/runtime/targets/$1.target"
    T_TRIPLE="" T_CFLAGS="" T_PARTS="" T_LAYOUT=""
    # shellcheck source=/dev/null
    . "$_m"
    rm -rf "$2" "$2.new" "$2.err"
    mkdir -p "$2.new"
    _bcs=""
    for _p in l0rt.ll freestanding.ll $T_PARTS; do
        _bc=$(echo "$_p" | sed -e 's|/|-|g' -e 's|\.ll$|.bc|')
        # shellcheck disable=SC2086
        if ! "$CC" --target="$T_TRIPLE" $T_CFLAGS -O2 -Wno-override-module -c \
            -emit-llvm "$ROOT/runtime/$_p" -o "$2.new/$_bc" 2> "$2.err"; then
            rm -rf "$2.new"
            return 1
        fi
        _bcs="$_bcs $_bc"
    done
    rm -f "$2.err"
    cp "$ROOT/runtime/$T_LAYOUT" "$2.new/layout.ld"
    cp "$_m" "$2.new/target"
    cp "$ROOT/tools/virt/Dockerfile" "$2.new/Dockerfile"
    echo "$_bcs" > "$2.new/parts"
    mv "$2.new" "$2"
}
