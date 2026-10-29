# 0131: the hidden whole copy of a map or array, shown before it bites

Kind: tooling, then perhaps language
Status: done, changelog "The hidden whole copy, named where an agent will
see it"; a checker warning left for a program that earns it
Needs: nothing

## Why

L0S's request 4 (its `build/l0-requests.md`, 2026-10-29): a map or
array "is changed in place unless something else still holds it, in
which case it is copied whole" (spec 6.5, `l0 doc Map`). L0S hit it
twice in one session, both seen only as a slowdown on real data:

- `(Pages (map_put m va f) (if (map_has m va) ...))`: `m` read after
  the put, so every put copied the map. A process mapping 100,000 pages
  became quadratic, and a test that took 12 s did not end in an hour.
- `(let s (dispatch k p ...) (... (proc_pid p) ...))`: `p` used after a
  call that updates a map inside `p`, so that map was copied once per
  call.

Asked: `l0 check` warns where a map or array is read, or its holder
used, after an update that would then copy it whole; or `l0 doc Map` and
the `l0-code` skill show the trap with an example.

## Done when

- first, the tooling half: the `l0-code` skill and `lib/AGENTS.md` name
  this trap beside quadratic output, with both of L0S's shapes and their
  fixes; `l0 doc Map`, `l0 doc array_set`, and the rest of the updates
  say it in their comments; an example in `lib/examples.l0` with its
  test
- then a decision, recorded here: whether the checker can see this. The
  emitter already knows a value's last use (spec 6.5's rule), so a use
  after an update of the same value is visible to it; a warning would be
  L0's first, and needs spec wording for what a warning is. If yes, it
  becomes a language item of its own in the queue.

## Log

- 2026-10-29: opened from L0S's request 4. Next: the docs and skill.
- 2026-10-29: the tooling half done, by a worker for the skills,
  `lib/AGENTS.md` ("Three traps specific to L0"), and `lib/examples.l0`'s
  `see_key`, `new_keys`, and `map_logged` with their tests, and here for
  the comments of Map, `map_put`, and `map_remove`, `array_set`'s row in
  section 6's table, and spec 6.5's sentence on a value used after a call
  that updates inside it; changelog "The hidden whole copy, named where an
  agent will see it". Measured with `L0_ARRAY_STATS=1`, 20,000 puts: both
  shapes 39,998 copies, 1.2 billion words, 1.6 s; read first, none, 5 ms.
  `(map_put m i (add 1 (map_size m)))` made none, so the variable-operand
  rule of 10.3 covers prelude calls, as 6.5 says. `l0 doc` shows no
  builtin, so `array_set` is documented by the spec alone. Left open: a
  checker warning, which would be L0's first, and needs a program that
  the docs did not save from the trap to earn it.
