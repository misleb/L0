# 0047: the compiler uses type parameters and eq

Kind: language
Status: done, changelog "The compiler is written with type parameters and
eq, and no language change for it"
Needs: 0046

## Why

[0044](0044-compiler-free-of-stage0.md) and
[0035](0035-type-parameters.md): with the prelude generic, the compiler
still carries 19 per-type `rev`, `length`, and `append` copies
(`rev_diags_onto`, `rev_tys_onto`, `length_exprs`, `append_sigs`, ...), 73
calls to `list_eq` and the hand-written `ty_eq`, `tys_eq`, and `bools_eq`
that `eq` replaces, and nine parser and checker result types of one
`Result` or `Option` shape.

## Done when

- the per-type copies are gone, and their callers use the prelude's
- `eq` replaces `list_eq`, `ty_eq`, `tys_eq`, and `bools_eq` in the compiler,
  where it is the same comparison
- the result types are `Option` or `Result`, unless one carries something
  those cannot, which the Log names
- both suites green, the fixpoint holds, the seed refreshed, and the
  changelog says what the compiler gave up writing by hand. Split by file
  if one change is too large to review

## Log

- 2026-10-05: queued by 0044.
- 2026-10-05: done, in four steps, each type checked, bootstrapped, and run
  through the fast suite before the next:
  - A: the 19 per-type copies became calls to `rev_onto`, `rev`, `length`,
    and `append`; `list_eq` (73 calls), `ty_eq`, `tys_eq`, and `bools_eq`
    became `eq`. `ro_same` stays, since it compares only the flags of two
    lists of functions; its comparison is `eq`
  - B: `FindSig`, `FindTy`, `FindCtor`, `FindData` became `Option`
  - C: `CTy`, `CTys`, `Binds` became `(Checked T)`, with `COk` and `CErr`
  - D: the parser's nine types became `(Parsed T)`, with `POk` and `PErr`,
    and `parse_arm` and `parse_ctor` return one arm or constructor
  - not `Result`, for C and D: their constructors carry two fields, an
    offset and a message on failure and the remaining tokens beside a
    parser's value, and `Result`'s carry one, so every error would be
    wrapped in a `Diag` and unwrapped by a second match, and a parser's
    success would need a pair the library lacks (reasons in the changelog)
  - equivalence: `build/stage1.ll` (the old seed compiling the new source)
    equals `build/stage2.ll` (the new compiler compiling it), and the old
    and new compiler give identical output on all 87 programs in
    `tests/check`, `tests/lang`, and `tests/io`
  - both suites green (63, 110); fixpoint at 1,157,183 bytes (from
    1,167,452); self-compile 0.15 s, as before; seed refreshed and
    reproduces itself; `tools/l0` rebuilt from it passes `lists_test`.
    README "How L0 grows" and `list_eq`'s doc no longer say the compiler
    carries copies or needs `list_eq`. No Linux run: the runtime and the
    emitter's output are unchanged, and 0045's runs are still owed
  - a tool note for the next agent: an Edit whose replacement ends in a
    space can lose that space, which turned `(list_eq n` into `(eqn`; the
    checker caught every one. Match on the name without the trailing space
    instead
  - next: the queue is empty
