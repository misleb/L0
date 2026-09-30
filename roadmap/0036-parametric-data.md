# 0036: Data types take type parameters

Kind: language
Status: queued
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
