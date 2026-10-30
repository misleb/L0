# 0140: string literals as byte tables

Kind: tooling
Status: done
Needs: nothing

## Why

The emitter turns a string literal into one `l0_new_cons` call per byte
(`emit_string`, emit.l0): the seed holds about 15,000 of them, and the
compiler's diagnostic strings are most of its 1.9 MB. Emitting each
literal as a private constant byte array and one call of a runtime
function that builds the list from it shrinks the seed, speeds every link,
and changes no program's meaning. The measure: the seed's size and
`tools/bootstrap.sh`'s time, before and after.

## The change

- `runtime/l0rt.ll`: `@l0_string(ptr, i64)`, building the list from the
  bytes, append-only in 10.3's interface
- `compiler/emit.l0`: a literal becomes a module-level constant, named for
  its number, and a call; the constants are emitted in a fixed order, so
  10.4's determinism holds
- spec 10.3 lists the function; nothing in sections 1 to 9 changes

## Done when

- the checklist in the l0-bootstrap skill, the fixpoint among it
- `bundle_prelude` and `emit_tail` re-blessed and the diff read
- the seed refreshed, and the changelog records the sizes and times
- `roadmap/l0s-adoption.md` notes it: nothing to change, builds faster,
  and process images built before and after mix freely

## Log

- 2026-10-30: opened, from the review (its item 1.6); proposed.
- 2026-10-30: done. Literals are deduplicated per module, which the item
  did not ask, since the compiler repeats many. Seed 2,132,675 to
  1,276,525 bytes, bootstrap 19.7 s to 16.9 s, `--virt` about 245 s to
  192 s; the three IR goldens gained only the `declare`. Measuring found
  0139's fixpoint had made self-compile 1.05 s; it is 0.78 s now (the
  changelog has both). Both suites, the fixpoint, and `--virt` on both
  boards green; the seed refreshed.
