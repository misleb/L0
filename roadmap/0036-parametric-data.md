# 0036: Data types take type parameters

Kind: language
Status: done, changelog "Data types take type parameters"; Linux run with 0044
Needs: 0035

## Why

[0035](0035-type-parameters.md)'s finding. Programs write the same result,
option, and pair types once per element type: 0014's json has `PJ` and `PS`
and a function that only moves an error from one to the other, kvstore has
five result types, 0028's mst has `UF` and `Found`, and the compiler has ten
`Result`-shaped types it cannot share. What cannot be written today:

```
(data (Option T)
  (None)
  (Some T))
```

```
opt.l0:1:7: error: a data declaration needs an uppercase type name
```

## Design, from 0035

- a `data` header may be `(Name P ...)`, its parameters upper names scoped
  to the declaration; a type may be `(Name type ...)` with exactly that
  many arguments
- functions stay monomorphic: every expression still has a concrete type
- a constructor's type is found from its arguments, each matched one way
  against its declared field type, as `cons` finds its type from `xs`; a
  parameter no field mentions (`None`) must be written, as `nil` writes its
  element type. The form is to be settled in the spec
- a `match` substitutes the subject's arguments into the fields' types
- no runtime change: `ctor_mask` is computed over substituted field types
- stage 0 cannot run it; tests go to the compiled suite. `lib/prelude.l0`
  and the compiler do not use it (0035: stage 0 runs both)

## Done when

- the l0-bootstrap checklist, with a failing case per new error (wrong
  number of type arguments, an undetermined parameter left unwritten, a
  parameter used outside its declaration, a field of the wrong type)
- a test that a `(Pair int (list int))` and a `(Pair (list int) int)` get
  the right masks: no leak and no double free under `L0_RC_CHECK`
- the shipped l0-code skill and `lib/examples.l0` show one parametric type

## Log

- 2026-09-30: queued from 0035.
- 2026-09-30: done. The form 0035 left open is `((None int))`: `((` begins
  no expression, so the parser needs no table of type names, and `(None
  int)` could not tell `(None (Pair int bool))` from a construction. It may
  be written for any constructor of a parametric type, and must be for one
  that does not determine every parameter. A parameter hides a data type of
  the same name within its declaration.
  - parser: `TyData` carries arguments, `DData` parameters, `ECtor` the
    written type arguments; types `(Name type...)`
  - checker: `ty_problem` replaces `unknown_ty` and also reports a wrong
    number of arguments; one-way `match_ty` finds a construction's type;
    `match` binds fields at substituted types. The emitter shares
    `ctor_type_args` and `ctor_fields_at` with it, so masks come from the
    bindings the checker accepted
  - emitter: the read-only analysis needed exact field types, not just the
    masks. With a field left as `T`, `(head rows)` for `rows` of type `(list
    (list int))` would count as a read yielding no pointer, and a caller
    would free a row it had just been handed. `ro_tail_demote` now carries
    each read-only name's type for that; `tests/io/parametric_data.l0`'s
    `first_row` is the case
  - tests: `tests/compiler/check_params` (34 snippets, stage 0 and compiled
    agree), `tests/io/parametric_data` under `L0_RC_CHECK` (masks 4 and 2
    for the two `Pair`s, 10 for `(Tree int)`'s `Node`), `parse_basic`
    round-trips the syntax; `check_errors` re-blessed for one reworded
    message, `expected list, array, or a data type name after ( in a type`
  - both suites green, fixpoint holds, seed refreshed. Linux runs owed:
    the emitter changed and Docker was not running
- 2026-10-05: the Linux runs happened with 0044, whose tree includes this
  change: both suites green on arm64 and amd64 (63 and 110).
