# 0063: tooling: the doc and tool findings of 0055

Kind: tooling
Status: done, changelog "A declaration that does not parse is reported
once, and no language change for it"
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
- 2026-10-07: done, each finding fixed:
  - **the cascade**: `parse_decls` keeps the name of each def that fails to
    parse, and `compile` drops "unknown function" and "unknown variable"
    for those names. 0055's `limits/03` and `07` now give one error each,
    where they gave two; `tests/check/parse_dropped_def` pins it (three
    errors before)
  - **the data parameter**: `starts_decl` takes `(def` or `(data` for a
    declaration only when a `(`, or a name and a `(`, follows, so
    `((data int))` is no longer one. A first try that also required the
    name's case lost `tests/check/names`'s error for `(def Upper_function`,
    which the suite caught; the rule now ignores case.
    `tests/check/param_named_data` gives one error, where it gave three
  - **`l0 check` without `main`** and **where `l0 run` builds**: said in
    `lib/AGENTS.md`, with the one-error behaviour above
  - **hexadecimal**: `hex_digits` in the prelude, unsigned over the 64 bits
    with bit operations from 0058, tested in `tests/unit/text_test.l0`,
    with `digits` and a round trip through `hex_val`
  - **`map_keys`**: its doc says a generic caller cannot order the keys;
    0059 decides whether anything will
  - **the wrappers' cost**: re-measured with 0055's `exp/` on 100 MB to four
    outputs: a list of `IoFile` 1.85 s, an array of `IoFile` 1.38 s, raw
    handles 0.67 s, so 2.8 and 2.1 times, most of it the wrapper rather than
    the list. The shipped skill says so, and how to take the handles out
  - **"failed on write"**: the shipped skill says no write returns a
    failure, and only a flush after it can tell which write it was
  - both suites green (65, 125); fixpoint at 1,249,341 bytes, seed
    refreshed, since the compiler and the prelude changed, and reproduces
    itself. No Linux run: neither the runtime nor the emitter changed
