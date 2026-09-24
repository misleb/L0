#!/bin/sh
# measure.sh -- time when output appears relative to input, for the nearest
# L0 program to "ask a name, greet it" (limits/04-no-output-before-eof.l0),
# and for a four-line sh program that does the task, as the reference for
# what a correct prompt looks like under the same harness.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tl="$here/../common/timeline.py"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/prompt.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

"$root/tools/l0" build "$here/../limits/04-no-output-before-eof.l0" -o "$tmp/l0prompt"
cat > "$tmp/shprompt" <<'EOF'
#!/bin/sh
printf 'What is your name? '
read -r name
printf 'Hello, %s!\n' "$name"
EOF
chmod +x "$tmp/shprompt"

echo "## A: the user answers at t+3 and then input ends, as in (sleep 3; echo Ada) | prog"
echo
echo "L0 (limits/04):"
python3 "$tl" --at 3 'Ada\n' --eof 3 -- "$tmp/l0prompt"
echo
echo "sh reference:"
python3 "$tl" --at 3 'Ada\n' --eof 3 -- "$tmp/shprompt"
echo
echo "## B: the answer is readable at t+0; end of file comes only at t+3"
echo
echo "L0 (limits/04):"
python3 "$tl" --at 0 'Ada\n' --eof 3 -- "$tmp/l0prompt"
echo
echo "sh reference:"
python3 "$tl" --at 0 'Ada\n' --eof 3 -- "$tmp/shprompt"
