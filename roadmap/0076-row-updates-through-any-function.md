# 0076: a row of an array updates in place through any function

Kind: language
Status: done, changelog "An element of an array updates in place through
any function"; passed on Linux arm64
Needs: 0074

## Why

[0074](0074-route-to-a-microkernel.md)'s `progs/kloop.l0` is an L0
kernel's loop with `user_run` simulated: a table of three 102-word
contexts, and per trap one context handed to a function that consumes it
and returns it updated. Written the natural way, the table copies the
context on every trap:

```
(def natural ((g (array (array int))) (k int) (n int)) (array (array int))
  (if (ge k n)
      g
      (let t (mod k 3)
        (natural (array_set g t (sim_run (array_get g t) k)) (add k 1) n))))
```

```
$ tools/l0 build roadmap/0074/progs/kloop.l0 -o tmp/0076/kloop
$ L0_ARRAY_STATS=1 tmp/0076/kloop natural 1000000
1000000
48
l0: array copies: 1000000
l0: array sets in place: 2000000
l0: array words copied: 102000000
```

48 ns a trap, every one a copy. That is what section 6.5 says: its one
in-place form for a row is a nested `array_set`, and here `array_get`
gives the row a second holder while `g` keeps it. Taking the row out
first, with an empty array left in its place, updates in place, 12 ns and
2 copies over the same million:

```
(let c (array_get g t)
  (let g1 (array_set g t hole)
    (take (array_set g1 t (sim_run c k)) hole (add k 1) n)))
```

That is a workaround, and an agent writing a kernel will not find it.

## Done when

- the checklist in the `l0-bootstrap` skill
- section 6.5 says when `(array_set g y (f (array_get g y) ...))` updates
  the row in place for any function or builtin `f`, generalizing the nested
  form of 0025: what `g` and `y` may be, that no other argument may use
  `g`, and what is evaluated in what order, so that errors still come in
  the order the written form gives. Section 10.3 says what the compiler
  emits, and the changelog why the row may be taken out while `f` runs,
  which no program can observe
- `kloop.l0`'s natural mode updates in place: copies only from `array_new`
  sharing its rows, checked with `L0_ARRAY_STATS`, and a test pins it
- the compiler's own source may use the form only after a seed refresh,
  per the two-step rule; this item does not need it to

## Log

- 2026-10-09: opened by 0074's recommendation, item 2, and queued at the
  user's request.
- 2026-10-09: done. Section 6.5's form is now `(array_set g y (f ...
  (array_get g y) ...))` for any function or builtin `f`, `g` one variable
  no other argument of `f` mentions, `y` the same variable or literal, and
  an element of any counted type; the nested form is its instance with `f`
  the builtin `array_set`, and keeps `l0_array_set_row`, so what it emits
  is unchanged. For any other `f` the compiler rewrites the argument to an
  internal call no program can write, emitted as the new
  `l0_array_take(g, y)`: it checks `y` where the argument stands, and moves
  the element out, leaving 0, when `g`'s count is 1, or adds a reference
  otherwise, allocating nothing either way, so errors and allocation come
  as the plain reading has them. `kloop.l0`'s natural mode: 2 copies in a
  million, both from `array_new`, 7 ns a trap, against 48 before and 10
  for the workaround. Tests: `tests/io/array_through` (`.sh`, four modes
  under `L0_ARRAY_STATS` and `L0_RC_CHECK`: through and list copy nothing,
  shared copies 4 and leaves the other table unchanged, mentions copies
  every step as the form does not apply), `array_through_order` and
  `array_through_late` (the index checked where the argument stands);
  `bundle_prelude` and `emit_tail` for the `declare`. The compiler's own
  source does not use the form. The shipped skill and the examples teach
  it, with `tally_at`. Fixpoint holds and the seed is refreshed. Both
  suites green (65, 138), `--virt` 73 passed and 53 skipped, Linux arm64
  green (65, 138).
