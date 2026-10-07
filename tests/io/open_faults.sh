#!/bin/sh
# open_faults.sh EXE -- each failure an open can report arrives as its case,
# with its words, and a case that kind of open cannot report does not
# compile.
set -eu
exe=$1
root=$(cd "$(dirname "$0")/../.." && pwd)
d=$(mktemp -d "$(dirname "$exe")/open_faults.XXXXXX")
trap 'chmod -R u+rwx "$d" 2> /dev/null; rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }
want() {
    got=$("$exe" "$1" "$2")
    [ "$got" = "$3" ] || fail "$1 $2: got \"$got\", want \"$3\""
}
want_mv() {
    got=$("$exe" mv "$1" "$2")
    [ "$got" = "$3" ] || fail "mv $1 $2: got \"$got\", want \"$3\""
}

printf 'x' > "$d/there"
want r "$d/there" "opened"
want r "$d/missing" "OpenMissing: no such file"
want r "$d" "OpenIsDirectory: is a directory"
want w "$d/new" "opened"
want w "$d/nodir/new" "CreateNoDirectory: no such directory"
want a "$d/nodir/new" "CreateNoDirectory: no such directory"
want w "$d" "CreateIsDirectory: is a directory"
want a "$d" "CreateIsDirectory: is a directory"

# Renaming (spec 6.3): onto a directory, empty or not, into a directory that
# does not exist, and a rename that works.
mkdir "$d/empty" "$d/full"
printf 'x' > "$d/full/inside"
printf 'x' > "$d/from"
want_mv "$d/from" "$d/empty" "RenameIsDirectory: is a directory"
want_mv "$d/from" "$d/full" "RenameIsDirectory: is a directory"
want_mv "$d/from" "$d/nodir/to" "RenameNoDirectory: no such directory"
want_mv "$d/from" "$d/to" "Done"
[ -f "$d/to" ] && [ ! -e "$d/from" ] || fail "the rename did not happen"

# Missing is only what the host looked for and did not find (spec 6.3): a
# missing directory on the way, or a file where a directory should be. A
# loop of links and a name too long to look up are other failures.
want r "$d/nodir/file" "OpenMissing: no such file"
want r "$d/there/file" "OpenMissing: no such file"
ln -s loop "$d/loop"
want r "$d/loop" "OpenFailed: input or output failed"
want r "$d/loop/file" "OpenFailed: input or output failed"
long=$(printf '%0300d' 0)
want r "$d/$long" "OpenFailed: input or output failed"
want m "$d/missing" "RenameMissing: no such file"
want m "$d/nodir/file" "RenameMissing: no such file"
want m "$d/loop/file" "RenameFailed: input or output failed"
want m "$d/$long" "RenameFailed: input or output failed"

# Permission bits stop neither root nor every filesystem, Docker's bind
# mounts among them, so these are checked only where they are enforced.
printf 'x' > "$d/locked"
chmod 000 "$d/locked"
if ! cat "$d/locked" > /dev/null 2>&1; then
    want r "$d/locked" "OpenDenied: permission denied"
    want w "$d/locked" "CreateDenied: permission denied"
    want a "$d/locked" "CreateDenied: permission denied"
fi
chmod 600 "$d/locked"
mkdir "$d/shut"
printf 'x' > "$d/shut/file"
chmod 000 "$d/shut"
if ! cat "$d/shut/file" > /dev/null 2>&1; then
    want r "$d/shut/file" "OpenDenied: permission denied"
fi
chmod 700 "$d/shut"
# A directory that may not be written: creating in it, and renaming out of
# it, are denied.
mkdir "$d/ro"
printf 'x' > "$d/ro/file"
chmod 500 "$d/ro"
if ! (: > "$d/ro/probe") 2> /dev/null; then
    want w "$d/ro/new" "CreateDenied: permission denied"
    want_mv "$d/ro/file" "$d/out" "RenameDenied: permission denied"
fi
chmod 700 "$d/ro"

# The mistake roadmap item 0049 began from: a missing directory taken for a
# missing file. Creating a file has no such case, so it does not compile.
cat > "$d/wrong.l0" <<'EOF'
(def main () int
  (match (open_out "no/such/dir/notes")
    ((IoFailed fault why) (if (eq fault (OpenMissing)) 2 1))
    ((IoOpened f) (let c (file_close f) 0))))
EOF
if "$root/tools/l0" check "$d/wrong.l0" > "$d/out" 2> "$d/err"; then
    fail "a case open_out cannot give type checked"
fi
grep -q "the second argument of eq must be CreateFault, but this is OpenFault" \
    "$d/err" || fail "the wrong case was rejected for another reason: $(cat "$d/err")"
