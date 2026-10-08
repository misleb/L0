# 0065: tooling: the library sorts and takes min and max of any type

Kind: tooling
Status: done, changelog "The library sorts, and takes the min and max, of
any type, and no language change for it"
Needs: 0064

## Why

[0059](0059-compare-or-function-values.md) counted about 15 int `min` and
`max` one-liners in 13 files, and every sort here written for one element
type: 0014's and 0028's wordfreq, 0028's insertion sort of lines and its
Kruskal merge sort, and 0055's heap and set twice over. With 0064's
`compare`, each is written once. The prelude is compiler source, so its use
of `compare` waits for a seed that knows it.

## Done when

- the prelude has a generic, stable `sort` of a list by `compare`, linear
  in stack and n log n in time, and `min` and `max`; documented, tested at
  ints, strings, and a record, and the library's own int `max` callers moved
  onto it where they read better
- the examples show ordering by a key, such as count descending then word
  as `(Key (neg count) word)`; both `l0-code` skills say how, and that a
  structural order is not a numeric one for a representation such as
  0055's bignums, whose limbs run least significant first
- `map_keys`'s doc points to `sort`
- both suites green, and the seed refreshed, since the prelude changed

## Log

- 2026-10-07: proposed by 0059.
- 2026-10-08: done.
  - prelude: `sort`, a bottom-up merge sort of runs of one, every loop a
    tail call; `min` and `max`, the first argument on a tie. A million ints
    sort in 0.25 s of user time on a 1 MB stack with nothing left live under
    `L0_RC_CHECK`
  - not documented as stable: `compare` is 0 only for equal values, so
    stability cannot be observed; the changelog says when it could be
  - tests: `tests/unit/sort_test.l0` (6 tests: edges, ints at their limits,
    strings, a `Rank` key, `min` and `max`, and 200,000 pseudo-random ints
    checked for order and for the same elements by counts)
  - examples: an ordering section, `by_frequency` (a map's words most
    frequent first, by sorting `Rank` keys) and `smallest` over `min`, each
    tested. The shipped skill and `lib/AGENTS.md` say to use `sort`, `min`,
    and `max` rather than write them; `map_keys`'s doc says to sort its keys
  - the library's int max callers: none read better as the generic one
    (`examples.l0`'s `max2` teaches `if`; the compiler's two are folds)
  - `tests/io/libdoc/index.txt` re-pinned with the three new entries
  - both suites green (65, 129); fixpoint at 1,270,613 bytes, seed
    refreshed, since the prelude is compiler source, and reproduces itself.
    No Linux run: neither the runtime nor the emitter changed
