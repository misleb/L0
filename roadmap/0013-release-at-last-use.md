# 0013: Release a value at its last use, not at the end of its scope

Kind: language
Status: dropped
Needs: nothing

## Why

From [0010](0010-reference-counting.md)'s measurements. 0006's line filter,
`0006/linefilter/linefilter.l0`, takes its whole input:

```
(def main ((input (list int))) (list int)
  (rev (filter_onto input (nil int) (nil int))))
```

At 100 MB of input it held 2.7 GB, and 0010 attributed that to `main`'s
parameter keeping the whole list alive, since the call is not in tail
position. That attribution was wrong; see the Log.

## Log

- 2026-09-24: opened from 0010's measurements.
- 2026-09-24: **dropped, because its blocker was misdiagnosed.** The cheapest
  version was built first, to test whether the idea was worth its cost: a
  list- or data-typed variable used exactly once in its scope, and not inside
  a branch, hands over its reference at that use instead of adding one and
  releasing later. It bootstrapped to a fixpoint and left nothing live under
  `L0_RC_CHECK`, and changed nothing measurable:

  | | before | with the rule |
  |---|---|---|
  | 0006 line filter, 100 MB input | 2.7 GB | 2.5 GB |
  | compiler compiling itself | 26.3 MB, 0.15 s | 26.0 MB, 0.15 s |

  A `main` that takes 100 MB of input and ignores it peaks at 2,504 MB, the
  same as the line filter with the rule. So the cost is the input list the
  runtime builds in full before `main` starts, one 24-byte cons cell per
  byte, and no rule for when to release can reduce it. Only the streaming
  `main` avoids it, which the l0-code skill already recommends. The rule was
  reverted, since a change has to be earned by what it makes possible, and
  this one made nothing possible. The 0010 changelog entry carries a
  correction.

  If the compiler's speed, 0.15 s against 0.04 s before counting, ever needs
  recovering, eliding increment and release pairs is the place to look, and
  this rule is a starting point; on its own it removed about 2% of the
  compiler's emitted IR and no measurable time.
