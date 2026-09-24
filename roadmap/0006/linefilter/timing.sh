#!/bin/sh
# timing.sh -- feed linefilter one line per second, as a log being written
# would (tail -f app.log | linefilter), and timestamp when matches appear.
# grep --line-buffered, under the same harness, is the reference.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tl="$here/../common/timeline.py"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/linefilter.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

"$root/tools/l0" build "$here/linefilter.l0" -o "$tmp/linefilter"

feed() {
    python3 "$tl" --at 0 'ERROR one\n' --at 1 'ok\n' --at 2 'ERROR two\n' \
        --eof 3 -- "$@"
}

echo "linefilter:"
feed "$tmp/linefilter"
echo
echo "grep --line-buffered ERROR (reference):"
feed grep --line-buffered ERROR
