# 0013: Release a value at its last use, not at the end of its scope

Kind: language
Status: proposed
Needs: nothing

## Why

From [0010](0010-reference-counting.md)'s measurements. 0006's line filter,
`0006/linefilter/linefilter.l0`, takes its whole input:

```
(def main ((input (list int))) (list int)
  (rev (filter_onto input (nil int) (nil int))))
```

`filter_onto` walks `input` with tail calls, but the call to it is an
argument to `rev`, not in tail position, so `main`'s parameter holds the head
of the list until `main` returns, and with it the whole list. At 100 MB of
input it holds 2.7 GB. Had `input`'s reference been handed to `filter_onto`
at its last use instead of incremented and released later, each cell would
be freed as the loop passed it.

## Open questions for this item

- The simplest cases may be enough: a variable used exactly once, or whose
  last use is the last thing evaluated on every path. How much of the general
  liveness analysis Perceus does is needed, and what it costs the emitter.
- Whether it is worth doing at all given the streaming `main`, which the
  l0-code skill already recommends for large inputs. A measurement on the
  compiler's own memory and on 0006's programs should decide.
- It also removes most increment and decrement pairs, which is where the
  compiler lost speed in 0010: 0.04 s to 0.15 s compiling itself.

## Done when

- the checklist in the `l0-bootstrap` skill, with every compiled program
  still passing under `L0_RC_CHECK`
- 0006's line filter holds memory proportional to one line plus its output,
  not to its input

## Log

- 2026-09-24: opened from 0010's measurements.
