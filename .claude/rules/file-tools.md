---
description: Read, create, and change files with the agent's file tools, not shell commands; keep the shell for building, testing, and git
alwaysApply: true
---

# Edit files with the file tools

Read, create, and change files with the agent's own file tools: the ones
that read a file, write a whole file, or replace an exact piece of one. Do
not edit through the shell.

```bash
# BAD
sed -i '' 's/old/new/' compiler/check.l0
cat > tests/io/foo.l0 <<'EOF' ... EOF
python3 - <<'EOF' ... open(p).write(s) ... EOF
cat spec/L0.md            # or head, tail, sed -n, to read a file
```

Shell edits each need the user's approval, and a reviewer sees a script
rather than the change it makes. They also fail quietly: a replacement
whose search text has drifted changes nothing and still exits 0, and the
mistake surfaces only when something reads the file later.

- To make several changes, make several edits, in parallel when they are
  independent. A long run of edits is fine; a script that bundles them is
  not.
- To read part of a large file, read that range with the file tool rather
  than `sed -n`.
- The shell is still right for running things: `tools/build.sh`,
  `tools/test.sh`, `tools/l0check`, `tools/l0`, `git`, and searching with
  `grep` or `git grep`. Writing a command's output to a file is running
  something, not editing, as in `tools/l0 doc > tests/io/libdoc/index.txt`.
- A subagent sees none of this: include this rule in its prompt.
