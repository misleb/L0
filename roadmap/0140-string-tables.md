# 0140: string literals as byte tables

Kind: tooling
Status: proposed
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

## Log

- 2026-10-30: opened, from the review (its item 1.6); proposed.
