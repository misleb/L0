#!/bin/sh
# remove.sh EXE -- each result spec 6.3 gives remove, and what it leaves:
# a file deleted, nothing there, a directory refused and kept, a link deleted
# and not what it leads to, and a handle open on the file still reading it.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/remove.XXXXXX")
trap 'chmod -R u+rwx "$d" 2> /dev/null; rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }
want() {
    got=$("$exe" "$1" "$2")
    [ "$got" = "$3" ] || fail "$1 $2: got \"$got\", want \"$3\""
}

printf 'x' > "$d/there"
want rm "$d/there" 0
[ ! -e "$d/there" ] || fail "the file is still there"
want rm "$d/there" -3
want rm "$d/nodir/file" -3

printf 'x' > "$d/plain"
want rm "$d/plain/file" -3

mkdir "$d/dir"
want rm "$d/dir" -5
[ -d "$d/dir" ] || fail "the directory went"

printf 'x' > "$d/target"
ln -s target "$d/link"
want rm "$d/link" 0
[ ! -e "$d/link" ] && [ ! -L "$d/link" ] || fail "the link is still there"
[ -f "$d/target" ] || fail "the file the link led to went"
ln -s dir "$d/dirlink"
want rm "$d/dirlink" 0
[ -d "$d/dir" ] || fail "the directory a link led to went"

printf 'x' > "$d/held"
want held "$d/held" "0 120 -3"

# Permission bits stop neither root nor every filesystem, so this is checked
# only where they are enforced.
mkdir "$d/shut"
printf 'x' > "$d/shut/file"
chmod 500 "$d/shut"
if ! (: > "$d/shut/probe") 2> /dev/null; then
    want rm "$d/shut/file" -4
    [ -f "$d/shut/file" ] || fail "a file that may not be deleted went"
fi
chmod 700 "$d/shut"
