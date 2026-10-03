---
description: All scratch files, built programs, and logs go in the repository's tmp/ folder, never outside $HOME/projects
alwaysApply: true
---

# Use the local tmp/ folder

Everything temporary lives in `tmp/` at the repository root: scratch L0
programs, binaries built from them, copies of the compiler, profiles, logs,
diffs, and measurement inputs and outputs. Its contents are git-ignored.

**Never create, copy, or run anything outside `$HOME/projects`.** That rules
out `/tmp`, `/private/tmp`, `$TMPDIR`, and `mktemp` without a path, and it
applies to L0 programs above all: build and run them only from inside the
workspace.

```bash
# BAD
cp build/l0c-native /tmp/l0prof && /tmp/l0prof < src.l0
tools/l0 build prog.l0 -o /tmp/prog
diff a b > /tmp/out.diff

# GOOD
mkdir -p tmp/prof && cp build/l0c-native tmp/prof/l0c && tmp/prof/l0c < src.l0
tools/l0 build prog.l0 -o tmp/prog
d=$(mktemp -d tmp/work.XXXXXX)
```

- Give each task its own subdirectory, such as `tmp/0027/`, and delete it
  when the task is done.
- `build/` is for the toolchain `tools/build.sh` and the bootstrap produce;
  don't put scratch work there.
- A subagent sees none of this: include this rule in its prompt. Worktree
  subagents (`best-of-n-runner`) are placed under `~/.cursor/worktrees`,
  outside `$HOME/projects`, so ask before launching one.
- If a command or tool can only write outside the workspace, stop and ask.
