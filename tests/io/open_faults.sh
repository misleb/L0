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

printf 'x' > "$d/there"
want r "$d/there" "opened"
want r "$d/missing" "OpenMissing: no such file"
want r "$d" "OpenFailed: input or output failed"
want w "$d/new" "opened"
want w "$d/nodir/new" "CreateFailed: input or output failed"
want a "$d/nodir/new" "CreateFailed: input or output failed"

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

# The mistake roadmap item 0049 began from: a missing directory taken for a
# missing file. Creating a file has no such case, so it does not compile.
cat > "$d/wrong.l0" <<'EOF'
(def main () int
  (match (open_out "no/such/dir/notes")
    ((IoFailed fault why) (if (eq fault (OpenMissing)) 2 1))
    ((IoOpened f) (file_close f))))
EOF
if "$root/tools/l0" check "$d/wrong.l0" > "$d/out" 2> "$d/err"; then
    fail "a case open_out cannot give type checked"
fi
grep -q "the second argument of eq must be CreateFault, but this is OpenFault" \
    "$d/err" || fail "the wrong case was rejected for another reason: $(cat "$d/err")"
