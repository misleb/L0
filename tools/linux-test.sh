#!/bin/sh
# Runs both test suites on Linux, in a local container.
#
# Usage: tools/linux-test.sh [arm64] [amd64]
#
# With no architecture, uses the host's. amd64 on an arm64 host runs under
# emulation and takes several times as long. The image is built from
# tools/linux/Dockerfile the first time and reused after; delete it with
# `docker image rm l0-linux-test:ARCH` to rebuild.
#
# The working tree, uncommitted changes included and build/ excluded, is
# streamed into the container rather than mounted, because a bind mount
# ignores the permission bits tests/io/filecopy.sh depends on.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ $# -eq 0 ]; then
    case $(uname -m) in
        arm64 | aarch64) set -- arm64 ;;
        x86_64 | amd64) set -- amd64 ;;
        *) echo "linux-test: unknown host architecture $(uname -m)" >&2; exit 2 ;;
    esac
fi

status=0
for arch in "$@"; do
    case $arch in
        arm64 | amd64) ;;
        *) echo "usage: tools/linux-test.sh [arm64] [amd64]" >&2; exit 2 ;;
    esac
    image=l0-linux-test:$arch
    if ! docker image inspect "$image" > /dev/null 2>&1; then
        echo "linux-test: building $image"
        docker build -q --platform "linux/$arch" -t "$image" "$ROOT/tools/linux" > /dev/null
    fi
    echo "== linux/$arch"
    if ! (cd "$ROOT" &&
          git ls-files -co --exclude-standard |
          while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done |
          COPYFILE_DISABLE=1 tar -cf - --no-xattrs -T -) |
        docker run --rm -i --platform "linux/$arch" "$image" sh -c '
            mkdir w && cd w && tar -xf - || exit 1
            uname -m && clang --version | head -1
            failed=0
            for suite in "" --compiled; do
                if tools/test.sh $suite > ../log 2>&1; then
                    tail -1 ../log
                else
                    cat ../log
                    failed=1
                fi
            done
            exit $failed'; then
        status=1
    fi
done
exit $status
