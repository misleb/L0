# 0038: Functions take type parameters

Kind: language
Status: done, changelog "Functions take type parameters"
Needs: 0036

## Why

[0035](0035-type-parameters.md): most of the lines that exist for want of
generics are helpers, not declarations: about 100 in the compiler (`rev_*`,
`length_*`, `append_*`, `find_*`), the prelude's `(list int)`-only `rev`,
`length`, and `append` with a copy for strings beside them, array grow
helpers rewritten in five 0028 programs, and 0014's trie written three
times. Parametric data alone removes none of these. What could not be
written:

```
(def (rev_onto T) ((xs (list T)) (acc (list T))) (list T)
  (if (is_empty xs) acc (rev_onto (tail xs) (cons (head xs) acc))))
```

```
why.l0:1:6: error: expected a function name after def
```

## Design, from 0035

- a parameter's type is matched one way against its argument's, so no
  inference; a result type mentioning a parameter no parameter mentions
  must be written at the call
- compiled once per combination of whether each type parameter's values
  are counted, which is the only thing `ty_is_ptr` asks, so no runtime
  change and no hidden argument
- no function values, so a generic container that compares keys still
  needs a comparison per key type; keys of `int`, `(list int)`, or `bytes`
  with values of any type cover every map in 0014 and 0028

## Done when

- the l0-bootstrap checklist, with a failing case per new error: a
  duplicated type parameter, one no parameter's type mentions, one given
  type arguments, an argument that gives one two types, a type parameter
  used as a particular type (`eq`, `match`, a return type), `main` with
  type parameters, and the parse errors of the new header
- a test under `L0_RC_CHECK` that both copies of a function count what
  their kind says, including a parameter read-only in one copy only
- the spec names the copies, and a test pins the names
- the shipped l0-code skill and `lib/examples.l0` show one generic function

## Log

- 2026-09-30: proposed by 0035.
- 2026-10-02: 0039 put `Option` and `Result` in the library and moved
  kvlog and the examples onto them; neither wanted a helper over them, so
  that is not yet the code this needs. Next: a program item that rewrites
  code 0035 counted as per-type helpers (0014's paths trie, the array grow
  helpers in 0028) with parametric data, to show which functions it wants
  first. Open question it must answer: a generic `rev` or `length` cannot
  sit beside the prelude's `(list int)` ones in one group, and the prelude
  cannot hold one while stage 0 runs it.
- 2026-10-02: started at the user's choice, without that program item; the
  Why is 0035's count and the program above. Done. Decisions (reasons in
  the changelog):
  - header `(def (name T ...) ...)`, as `data`'s; a type parameter is a
    type of its own inside the body, equal only to itself, so the body is
    checked once
  - every type parameter must be in some parameter's type, so no call
    writes types. 0035's design allowed a result-only parameter written at
    the call; left out until a program needs one, and `((f int) x)` is free
    for it
  - copies are `@l0_f_f.` plus one digit per type parameter, every
    combination emitted; LLVM deletes the unused, since they are internal
  - compiler: `DDef` and `Sig` carry type parameters, `Ctx` the ones in
    scope; `check_user_call` matches with 0036's `infer_fields`;
    `hide_tparams` renames a type parameter that names a data type to
    `f's T`, as 0037 renamed prelude types, so the two never compare equal;
    `mono_program`, at the end of `check.l0`, replaces each generic def by
    its copies with `int` or `(list int)` for each type parameter and
    renames calls by their arguments' types. It runs only when some def has
    type parameters, so the compiler's own output is unchanged. The emitter
    changed in one line, to run it
  - tests: `tests/compiler/check_fn_params` (30 snippets, both suites),
    `parse_errors` (5 cases) and `parse_basic` (a round trip),
    `tests/io/parametric_fns` under `L0_RC_CHECK` (copies of both kinds,
    `first_or` read-only only in `.0`, as the IR shows, tail calls between
    copies of different arities, a generic `rev` shadowing the prelude's,
    a generic def named like a builtin), `tests/io/parametric_fn_names`
    (copy names and which copy each call reaches)
  - both suites green (63, 106), fixpoint holds, seed refreshed. No Linux
    run: the runtime and the emission of each function are unchanged
  - follow-up proposed as [0040](0040-library-list-helpers.md): the
    library's list helpers for every element type
