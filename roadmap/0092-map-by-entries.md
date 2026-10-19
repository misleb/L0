# 0092: two maps holding the same entries are the same value

Kind: language
Status: done, changelog "Two maps holding the same entries are the same
value"
Needs: nothing

## Why

L0S's request: on the prelude's `(Map K V)`, `eq`, `hash`, and `compare`
saw how the table was built, not what it held. Two maps with the same
entries, built two ways, compared unequal, hashed apart, and missed each
other as keys:

```
(def test_overwritten () int
  (check_true "1 to b"
    (eq (map_put ((MapEmpty int (list int))) 1 "b")
        (map_put (map_put ((MapEmpty int (list int))) 1 "a") 1 "b"))))
```

gave false, as did six more cases of insertion order, removal, growth,
`hash`, `compare`, and a map as a key. L0S worked around it with
`vol_same`, comparing its volume's map key by key.

## Done when

- spec 6.8 and 6.9 say a data type is compared by its fields, and that
  the library's map is a function of its entries; the changelog says why
- `lib/prelude.l0`'s table is canonical: no fill values, capacity by
  count, Robin Hood placement with a total order; `map_eq` and
  `map_pairs` added and documented; `tests/io/libdoc` regenerated
- the reproduction in `tests/unit/map_test.l0`, with random maps against
  rebuilt ones; `same_elements` in the examples
- `tools/test.sh` and `--compiled` green, the fixpoint holds, and the
  compiler's speed measured before and after

## Log

- 2026-10-19: reproduced all seven of L0S's failures on HEAD. The user
  chose both the canonical table and `map_eq` with `map_pairs`. Done:
  suites 65 and 147 green, fixpoint holds, self-compile 0.25 s before and
  after, and the compiler emits the same bytes built with either map. Put
  is 30% slower, get unchanged (changelog). Seed not refreshed: the
  compiler learned nothing, and the seed compiles this prelude.
