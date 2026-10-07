#!/bin/sh
# remove.sh EXE -- each result spec 6.3 gives remove, as remove_file's case,
# and what it leaves: a file deleted, nothing there, a directory refused and
# kept, a link deleted and not what it leads to, and a handle open on the
# file still reading it.
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
want rm "$d/there" Done
[ ! -e "$d/there" ] || fail "the file is still there"
want rm "$d/there" RemoveMissing
want rm "$d/nodir/file" RemoveMissing

printf 'x' > "$d/plain"
want rm "$d/plain/file" RemoveMissing

mkdir "$d/dir"
want rm "$d/dir" RemoveIsDirectory
[ -d "$d/dir" ] || fail "the directory went"

printf 'x' > "$d/target"
ln -s target "$d/link"
want rm "$d/link" Done
[ ! -e "$d/link" ] && [ ! -L "$d/link" ] || fail "the link is still there"
[ -f "$d/target" ] || fail "the file the link led to went"
ln -s dir "$d/dirlink"
want rm "$d/dirlink" Done
[ -d "$d/dir" ] || fail "the directory a link led to went"

printf 'x' > "$d/held"
want held "$d/held" "Done 120 -3"

# Permission bits stop neither root nor every filesystem, so this is checked
# only where they are enforced.
mkdir "$d/shut"
printf 'x' > "$d/shut/file"
chmod 500 "$d/shut"
if ! (: > "$d/shut/probe") 2> /dev/null; then
    want rm "$d/shut/file" RemoveDenied
    [ -f "$d/shut/file" ] || fail "a file that may not be deleted went"
fi
chmod 700 "$d/shut"
