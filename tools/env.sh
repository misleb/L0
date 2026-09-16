# Shared configuration for the tools/ scripts. Sourced, not executed.
#
# ROOT must already be set by the caller.

: "${LLVM_PREFIX:=/opt/homebrew/opt/llvm}"

CC="$LLVM_PREFIX/bin/clang"
BUILD="$ROOT/build"

if [ ! -x "$CC" ]; then
    echo "error: clang not found at $CC" >&2
    echo "set LLVM_PREFIX to your LLVM installation" >&2
    exit 1
fi

export LLVM_PREFIX CC BUILD ROOT
