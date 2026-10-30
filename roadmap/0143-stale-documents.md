# 0143: documents that disagree with the code

Kind: tooling
Status: proposed
Needs: nothing

## Why

Each is small; together they cost trust in the files an agent reads first.
Found by the review of 2026-10-30:

- `README.md` says the Pi 5 "has not yet run on one"; 0098 and 0110 record
  runs on a 2 GB board on 2026-10-24
- `README.md` and `.gitignore` describe `.claude/skills` as a symlink into
  `.cursor/`; `git status` shows them as one file, so the words should say
  which is the link
- the root `AGENTS.md` names "Two traps"; `lib/AGENTS.md` names three. The
  root one says `bootstrap/stage2.ll`, "once it exists"
- the l0-code skill says the spec "is short"; the l0-bootstrap skill says
  "There are two boards" and frames `tools/linux-test.sh` as what "macOS
  alone won't show", on a Linux host whose clang cut the seed
- `lib/io.l0`'s header states a naming rule that `DeviceOpened`,
  `DeviceFault`, and `Trap` break (0144 fixes the names; this fixes the
  rule's words)
- the changelog cites `roadmap/0068/metal.ll`, `roadmap/0074/progs/`,
  `roadmap/0094/why.l0`, and `tmp/0110`, none of which exist, and the
  l0-roadmap skill says item directories are deleted when the item lands,
  while a dozen remain
- `roadmap/INDEX.md`'s "Current focus" is a 140-line narrative that stops
  at 0116; a table of goals and their state would replace it
- `README.md`'s "What L0 cannot do yet" does not say that L0 cannot run a
  process or read a directory, which is why `tools/l0` and `tools/test.sh`
  are 2,800 lines of shell

## Done when

- each line above is false
- `README.md` and the skills are read once through for anything else that
  no longer holds

## Log

- 2026-10-30: opened, from the review (its item 2.3); proposed.
