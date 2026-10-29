# 0131: the hidden whole copy of a map or array, shown before it bites

Kind: tooling, then perhaps language
Status: queued
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
