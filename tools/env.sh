# Shared configuration for the tools/ scripts. Sourced, not executed.
#
# ROOT must already be set by the caller.

BUILD="$ROOT/build"

# LLVM_PREFIX pins the installation when it is set. Otherwise prefer Homebrew's
# LLVM, whose clang is not the one on PATH on macOS, and fall back to PATH,
# which is where a Linux distribution puts it. Mirrors find_cc in tools/l0.
if [ -n "${LLVM_PREFIX:-}" ]; then
    CC="$LLVM_PREFIX/bin/clang"
    if [ ! -x "$CC" ]; then
        echo "error: clang not found at $CC" >&2
        exit 1
    fi
elif [ -x /opt/homebrew/opt/llvm/bin/clang ]; then
    LLVM_PREFIX=/opt/homebrew/opt/llvm
    CC="$LLVM_PREFIX/bin/clang"
elif command -v clang > /dev/null 2>&1; then
    LLVM_PREFIX=$(dirname "$(dirname "$(command -v clang)")")
    CC=clang
else
    echo "error: no clang found" >&2
    echo "set LLVM_PREFIX to your LLVM installation" >&2
    exit 1
fi

export LLVM_PREFIX CC BUILD ROOT
