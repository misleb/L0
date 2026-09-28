#!/bin/sh
# Installs the L0 toolchain into a relocatable prefix.
#
# Usage:
#   tools/install.sh [--prefix DIR]     default: $HOME/.local
#   tools/install.sh --into DIR         populate one library directory only
#
# Produces:
#   <prefix>/bin/l0              the driver
#   <prefix>/lib/l0/l0c          the compiler, built from bootstrap/stage2.ll
#   <prefix>/lib/l0/l0rt.o       the runtime, as bitcode for link-time optimization
#   <prefix>/lib/l0/prelude.l0   the standard library, which l0 doc documents
#   <prefix>/lib/l0/io.l0        line and string I/O, linked like the prelude
#   <prefix>/lib/l0/test.l0      assertions, linked by l0 test
#   <prefix>/lib/l0/L0.md        the specification, shown by l0 spec
#   <prefix>/lib/l0/examples.l0  worked examples, shown by l0 examples, with
#                                examples_test.l0 beside it
#   <prefix>/lib/l0/AGENTS.md    project invariants, copied by `l0 init`
#   <prefix>/lib/l0/skills/      agent skills, copied by `l0 init`
#
# Requires clang and nothing from L0: the compiler is built from the
# checked-in seed rather than from the L0 sources, so no existing L0
# toolchain is needed. clang specifically, because the runtime and
# bootstrap/stage2.ll are both LLVM IR text. No C is compiled.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tools/env.sh"

PREFIX="$HOME/.local"
LIBONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            PREFIX=$1
            ;;
        --into)
            shift
            LIBONLY=$1
            ;;
        *)
            echo "usage: tools/install.sh [--prefix DIR] | [--into DIR]" >&2
            exit 2
            ;;
    esac
    shift
done

if [ -n "$LIBONLY" ]; then
    LIBDIR=$LIBONLY
    BINDIR=""
else
    LIBDIR="$PREFIX/lib/l0"
    BINDIR="$PREFIX/bin"
fi

mkdir -p "$LIBDIR" "$BUILD"
[ -n "$BINDIR" ] && mkdir -p "$BINDIR"

# The runtime is installed as one bitcode object, not an archive: every link
# passes -flto to optimize a program and the runtime together, and indexing
# bitcode in an archive needs an ar that understands it, which not every host
# has. An archive left by an earlier install is removed.
echo "ll   runtime/l0rt.ll"
"$CC" -O2 -flto -Wno-override-module -c "$ROOT/runtime/l0rt.ll" -o "$BUILD/l0rt.o"
rm -f "$LIBDIR/libl0rt.a"
cp "$BUILD/l0rt.o" "$LIBDIR/l0rt.o"

echo "link compiler from bootstrap/stage2.ll"
"$CC" -O2 -flto -Wno-override-module "$ROOT/bootstrap/stage2.ll" \
    "$BUILD/l0rt.o" -o "$LIBDIR/l0c"

# In --into mode the destination is usually the repository's own lib/, where
# these files already live; copying them onto themselves would fail.
if [ "$(cd "$LIBDIR" && pwd)" != "$(cd "$ROOT/lib" && pwd)" ]; then
    echo "copy library, spec, examples, and agent files"
    cp "$ROOT/lib/prelude.l0" "$LIBDIR/prelude.l0"
    cp "$ROOT/lib/io.l0" "$LIBDIR/io.l0"
    cp "$ROOT/lib/test.l0" "$LIBDIR/test.l0"
    cp "$ROOT/lib/examples.l0" "$LIBDIR/examples.l0"
    cp "$ROOT/lib/examples_test.l0" "$LIBDIR/examples_test.l0"
    cp "$ROOT/spec/L0.md" "$LIBDIR/L0.md"
    cp "$ROOT/lib/AGENTS.md" "$LIBDIR/AGENTS.md"
    rm -rf "$LIBDIR/skills"
    cp -R "$ROOT/lib/skills" "$LIBDIR/skills"
else
    # The driver's init command reads L0.md from the library directory, so
    # give it one even when running straight out of the repository.
    cp "$ROOT/spec/L0.md" "$LIBDIR/L0.md"
fi

if [ -n "$BINDIR" ]; then
    cp "$ROOT/tools/l0" "$BINDIR/l0"
    chmod +x "$BINDIR/l0"
    echo
    echo "installed to $PREFIX"
    echo "  make sure $BINDIR is on your PATH, then:"
    echo "    l0 init myproject"
fi
