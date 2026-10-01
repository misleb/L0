# 0037: A program's types do not collide with the library's

Kind: language
Status: done, changelog "A program's types shadow the library's, and Io
names are no longer reserved"; Linux runs owed
Needs: 0036

## Why

[0035](0035-type-parameters.md): once 0036 lands, `lib/io.l0` should define
`Option`, `Result`, and a pair once for every program. But type and
constructor names are global across the prelude and the program (spec 7.1),
and twelve `.l0` files here already use `Ok`, `Some`, `Pair`, or the like
(0014's calc, 0028's json, kvstore's tests, `tests/lang/last_use.l0`,
`lib/examples.l0`). Adding them to the library would break every one, which
is what 0031 stopped for functions. Only names beginning `Io` are reserved
for the library today, which would make the shared types `IoOption` and
`IoResult`.

## The question for the spec

Whether a program's type or constructor shadows a library one of the same
name, as a program's function does, with the checker telling same-named
types apart by group despite 7.1's two reasons for keeping them global; or
whether the library's general types get names reserved some other way.

## Done when

- the l0-bootstrap checklist
- a program that defines its own `Ok` still compiles and runs with a
  library that defines one

## Log

- 2026-09-30: queued from 0035, after 0036.
- 2026-09-30: done. The user chose grouping over a reserved prefix, and to
  drop the `Io` reservation, which grouping leaves without a reason.
  - the earlier objection to grouping was about 44 resolution sites; none
    changed. `group_upper` in `compiler/check.l0` renames every upper name
    in a prelude declaration that the program also declares to `prelude's
    X`, skipping a data declaration's own parameters, and both
    `check_program` and `emit_module` run on the result. The checker's
    duplicate sets are still single, and are per group because of the
    renaming
  - tests: `tests/compiler/groups` (14 cases: spec 7.1's example, a
    shadowed constructor that cannot take the prelude's type apart, a
    same-named type as a different type, the prelude not seeing the
    program, duplicates within a group, a parameter not renamed, an `Io`
    name); `tests/io/shadow_types` declares its own `IoFile` and `IoEnd`
    and still opens and reads a file through `lib/io.l0`, under
    `L0_RC_CHECK`. `check_errors` and `prelude_scope` re-blessed: their
    four cases asserting a collision or a reserved name now check
  - found on the way: `tools/l0` uses `lib/l0c`, built from the seed, so
    trying a compiler change through it needs `L0_COMPILER` or a seed
    refresh
  - follow-up proposed as [0039](0039-library-option-result.md): the
    library can now declare `Option` and `Result` without breaking anyone
