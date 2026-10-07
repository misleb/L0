# 0063: tooling: the doc and tool findings of 0055

Kind: tooling
Status: proposed
Needs: nothing

## Why

[0055](0055-programs-round-three.md)'s workers found these, none a
language limit:

- after a declaration fails to parse, the checker drops it and reports
  every later use as an unknown function or variable, which misleads
  (`tmp/0055/numbers/limits/03`, `07`); a parameter named `data` gives a
  correct first error and then "a data declaration needs an uppercase type
  name"
- `l0 check` accepts a file with no `main`, which is useful and said
  nowhere in the shipped guide or skill (two workers)
- the shipped docs do not say where `l0 run` builds its program
- the library parses hexadecimal (`hex_val`) and cannot print it
- the prelude's "sort the keys if the order matters", above `map_keys`,
  cannot be followed for a generic key until 0059 lands
- the skill's "use the wrappers, not the raw builtins" says nothing of
  what a list of `IoFile` costs in a per-byte loop (2.7 times raw handles)
- a failure "on write" can only mean a flush during the copy found lost
  bytes; the shipped docs should say so

## Done when

- each is fixed, or recorded here as not worth fixing with the reason
- `tools/test.sh` and `tools/test.sh --compiled` green

## Log

- 2026-10-06: opened by 0055, with the user's agreement.
