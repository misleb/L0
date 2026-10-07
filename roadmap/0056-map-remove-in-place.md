# 0056: `map_remove` updates in place

Kind: language
Status: done, changelog "Removing a key from a map no longer copies it, and
no language change for it"
Needs: nothing

## Why

[0055](0055-programs-round-three.md)'s structures worker found that the
prelude's `map_remove` copies the map's marks array whenever it shifts an
entry back. `lib/prelude.l0`'s `map_shift` ends in

```
(map_shift (array_set ms i mj) (array_set ks i (array_get ks j))
           (array_set vs i (array_get vs j)) n j (map_next j ms))
```

whose last operand reads `ms` after the first operand's `array_set`, so that
`array_set` never holds the only reference (spec 6.5). A map held by nothing
else, sliding a 10,000-key window:

```
(def slide ((m (Map int int)) (i int) (n int) (w int)) (Map int int)
  (if (ge i n)
      m
      (slide (map_remove (map_put m i i) (sub i w)) (add i 1) n w)))
```

```
$ L0_ARRAY_STATS=1 tmp/0055/recheck/window 10000 200000
10000
l0: array copies: 84043
l0: array sets in place: 1007226
l0: array words copied: 2753921024
```

With the reads bound by `let` first (`tmp/0055/structures/hypothetical/
map_remove_fixed.l0`), 0 copies. It makes 0055's LRU cache five times
slower, and the doc's "amortized constant time" false.

## Done when

- `map_shift` binds its reads before its updates, and a test in the suite
  shows `map_remove` in a loop copies nothing under `L0_ARRAY_STATS`
- the rest of the prelude is read for the same pattern, and any other case
  fixed with it
- the l0-bootstrap checklist: both suites green, fixpoint, the seed
  refreshed (the prelude is compiler source), the changelog says what
  changed

## Log

- 2026-10-06: queued by 0055. Waits for 0055's workers to finish, since
  rebuilding replaces the toolchain they are running.
- 2026-10-06: done.
  - `map_shift` binds the next slot before updating `ms`; the reads of `ks`
    and `vs` inside their own `array_set`'s value operand were already
    fine, as section 6.5's `count` example is. No other update in
    `lib/prelude.l0`, `lib/io.l0`, or `lib/test.l0` reads its array in a
    later operand
  - `tests/io/map_remove_in_place`: a 1,000-key window over 200,000 keys,
    checking what is left and that nothing copies; on the old prelude it
    copies 191,044 times and fails
  - 0055's LRU cache, rebuilt on the library: the same output, 0.23 s of
    user time against 1.10 s on the old prelude
  - both suites green (63, 116); fixpoint at 1,218,142 bytes; seed
    refreshed and reproduces itself. No Linux run: neither the runtime nor
    the emitter changed
  - next: 0057
