# 0035: How L0 gets type parameters

Kind: research
Status: done; recommends 0036, then 0037, and proposes 0038
Needs: nothing

## Why

Data types take no type parameters, and no function but a builtin works at
more than one type (spec section 3: "types declared with `data` never take
type parameters"). It is the limit found most often, and each time it was
paid for rather than lifted:

- 0014, all three data-structure programs
  (`0014/data-structures/limits/03-no-type-parameters.l0`): about 100 of
  1,607 lines were copies (the same trie three times, `rev` three times, ten
  one-use result and state types), and the library cannot offer a map, set,
  heap, `Option`, or `Result` at all, since each would be written once per
  element type.
- 0028, all three workers: no pair type (a heap as one interleaved int
  array, the named workaround) and a one-use data type for every function
  returning two things.
- The compiler carries nine near-identical result types "for want of
  generics" (changelog, the entry retiring the request loop).
- The missing pair type shaped three recent designs: 0025 could not have a
  builtin return the old element, 0032's `read_bytes` returns no code beside
  its bytes, and 0033's `IoBytes` drops the bytes read before a failure.

## The question

What is the smallest change that lets the library define `Option`,
`Result`, a pair, and a map once, for every element type, and what does it
cost the properties the l0-bootstrap skill lists: no type inference (every
expression's type determined by itself), `list` and `array` the only
parametric constructors with no unification anywhere, the frozen stage-0
oracle, and reference counting that must know which values are pointers?

## Done when

- a finding in the Log that weighs, against spec sections 3, 5, 6, 10.1,
  and 10.3 and the compiler as it is:
  - parametric `data` alone, against parametric functions too
  - how a type argument is known at each use without inference, including
    for a constructor with no field of that type, as `nil` is today
  - how compiled code learns whether a value of type `T` is counted:
    one copy per instantiation, a hidden argument, or a uniform
    representation
  - what stage 0 can still check, and whether the compiler could use the
    feature, given that `tools/test.sh` runs the compiler's own sources
    under stage 0
- a count, from this repository's code, of what each option would remove
- the first language item, or items, it recommends, queued in INDEX

## Log

- 2026-09-30: opened at the user's choice, after 0034.
- 2026-09-30: **finding.** Two read-only surveys (the compiler and runtime's
  counting; the code that exists for want of generics), re-checked in the
  main tree.

  **What compiled code needs to know about a type is one bit.** Every value
  is an `i64` (10.1). Freeing never consults types: each block's header
  holds a mask of which words are pointers, which the compiler supplies at
  allocation (`l0_new_cons`'s 2 or 3, `l0_new_data`'s field bits,
  `l0_array_new`'s 1 or 0), and `free_block` walks it. The static type is
  used only to decide that mask and whether to emit `l0_inc` and `l0_dec`,
  and every such decision in `compiler/emit.l0` goes through one predicate,
  `ty_is_ptr` (line 103), about fifteen call sites, none asking anything
  else of a type. So:
  - **parametric `data` with monomorphic functions** needs nothing new at
    runtime and nothing like instantiation: every expression in every
    function still has a concrete type such as `(Option (list int))`, so a
    construction knows its field types, substituted, and a `match` knows
    its fields'. The change is the parser (a header `(data (Option T)
    ...)`, a type `(Option int)`), the checker (substitution when
    constructing and matching; structural equality already compares
    arguments), and the emitter's `ctor_mask` over substituted field types.
  - **parametric functions** need, per type parameter, only whether its
    values are counted. Compiling each at most once per combination of
    those bits (two copies for one parameter) is monomorphization by
    representation, not by type, keeps `ty_is_ptr` static inside each
    copy, and needs no runtime change and no hidden argument. A hidden
    argument would work too, but threads a bit through every polymorphic
    site and makes counting a runtime test; a uniform tagged representation
    would break 10.1 and the ABI outright, and is not worth weighing
    further.

  **No inference is needed for either.** The type of `(Some 5)` follows
  from its argument, matched one way against the declared field `T`, which
  is exactly how `cons` already takes its type from `xs`: no unification,
  every expression's type determined by its parts. The exceptions are a
  constructor none of whose fields mention a parameter, such as `(None)`,
  and, for functions, a result type mentioning a parameter that no
  parameter type does. Both are the case `nil` already has, and need the
  type written, as `(nil int)` does. The property that breaks is "`list`
  and `array` are the only parametric type constructors"; "no unification
  anywhere" and "no type inference" hold.

  **What it would remove,** counted from the code (exact for declarations,
  estimates marked):
  - compiler: eight parser result types `PTy` to `PDecl` (`parse.l0`
    104-134) plus `CTy` and `CTys` are one `Result` shape; `FindSig`,
    `FindTy`, `FindCtor`, `FindData` (`check.l0` 32-46) and `MaybeBody` are
    `Option`; about 45 lines of `rev_*_onto`, 8 of `length_*`, 11 of
    `append_*`, and 40 of `find_*`/`lookup_*` walks are per-type copies.
    Parametric data removes about 40 lines of declarations there;
    parametric functions about 100 more (estimate)
  - library: the prelude is `(list int)` only by its own header, and
    already carries a copy, `rev_strs_onto`, and `lib/test.l0` another,
    `strs_eq`. `IoLine`, `IoBytes`, and `IoOpened` are each one `Result`
    shape. The larger cost is what the library cannot offer at all:
    `Option`, `Result`, a pair, a map
  - 0014 and 0028 programs: 150 to 180 lines in 0014 (the trie three times
    in paths, about 50 redundant; `PJ` and `PS` in json with a function
    that only moves an error between them; five kvstore result types; the
    `Gen*` family), 80 to 120 in 0028 (array grow helpers rewritten in five
    programs; dijkstra's heap interleaved in one int array "since there is
    no pair type to make an array of"; mst's `UF` and `Found`)
  - declarations are the smaller share everywhere: most of the lines are
    helpers, which only parametric functions remove

  **Names are a prerequisite for the library.** Twelve `.l0` files here
  already use `Ok`, `Some`, `Pair`, or the like (calc, 0028's json,
  kvstore's tests, `tests/lang/last_use.l0`, `lib/examples.l0`). Type and
  constructor names are global across the prelude and the program (7.1),
  so a library `Result` with an `Ok` would break every one of them, the
  failure 0031 removed for functions. Types cannot simply be grouped as
  functions are, for 7.1's two reasons (a `match` arm names a constructor
  without its type; types compare by name), so this needs its own rule:
  a program type or constructor shadows a library one of the same name,
  with the checker telling same-named types apart by group, or the library
  keeps to reserved names.

  **Stage 0 and the compiler.** Bootstrap no longer uses stage 0 (it starts
  from the seed), but `tools/test.sh` runs `tests/compiler` and
  `tools/l0check` on the compiler's own sources under stage 0, which knows
  only ints, bools, lists, and data, and compiler goldens are blessed only
  that way. Programs, `lib/io.l0`, and `lib/test.l0` can use the feature,
  tested by the compiled suite as arrays and bytes are; `lib/prelude.l0`
  cannot. The compiler adopting it, which is where the nine result types
  are, would end the stage-0 run of the compiler's tests and needs a new
  rule for blessing them: a separate decision, not part of these items.

  **Recommended, in order:**
  1. [0036](0036-parametric-data.md), language: `data` takes type
     parameters; functions stay monomorphic. The smallest step, no runtime
     change, and it lets programs write `Option`, `Result`, and a pair
     once each.
  2. [0037](0037-library-type-names.md), language: a program's type or
     constructor does not collide with the library's. Needed before
     `lib/io.l0` can ship `Option`, `Result`, or a pair.
  3. [0038](0038-parametric-functions.md), proposed: functions take type
     parameters, compiled once per counted-or-not combination. Most of the
     measured lines, and the library's `rev`, `length`, and containers.
     Generic containers that compare keys would still need a comparison
     per key type, since L0 has no function values; keys of `int`, `(list
     int)`, or `bytes` with values of any type cover every map written here.
