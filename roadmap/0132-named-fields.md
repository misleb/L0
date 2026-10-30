# 0132: named fields, read and replaced by name

Kind: language
Status: active
Needs: nothing

## Why

A data type with several fields costs a function per field to read one and
a function per field to change one, each a `match` that names every field
to use one. The compiler has 47 such readers, one-line functions whose
whole body is a single-arm `match` returning one binding (`ctx_sigs` to
`data_max_fields`, compiler/check.l0:53-108; `env_binds` to `val_st`,
compiler/emit.l0:54-108), and the L0 kernel writes `(Kern ps q qo arr held
pa)` 22 times to change one field of a six-field value
(tests/virt/user/kernel.l0:99-132). The smallest program that cannot be
written: the state of a process, read and set without a function per
field.

```
(data Proc
  (Proc (space int) (ctx (array int)) (state int)))

(def stop ((p Proc)) Proc
  (.state p -1))
```

The checker, before this item: `tests/check/parens_stray.l0`-style
`unexpected character` at the `.`, since `.` begins only a float literal.

## Done when

- the checklist in the l0-bootstrap skill
- spec 2.4, 4, 5.8, 6.5, 7, and 10.3 state the rule; the changelog says why
- `tests/compiler/check_fields` holds the checker's verdicts,
  `tests/unit/fields_test.l0` the behaviour, and `tests/io/fields_in_place`
  shows 0 copies under `L0_ARRAY_STATS` for a loop that threads a record
  through replacements
- step 2, after the seed is refreshed: the compiler, the kernel, and the
  library name their fields, the 47 readers are gone, and the kernel's 22
  rebuilds are replacements; `L0_ARRAY_STATS=1` on the compiler compiling
  itself shows no copies from them

## Log

- 2026-10-30: opened, from the review that found the readers and the
  rebuilds. The syntax chosen: a field name is a token, `.` and a lower
  name, so no word is reserved and no existing program changes; `(.f e)`
  reads, `(.f e v)` replaces, in place by 6.5's rule; one constructor only;
  a constructor names all of its fields or none; `match` and construction
  stay positional. Before it, two fixes the review found: the lexer crashed
  on a source file whose last byte is a digit (`head` of the empty rest
  through a strict `and`, lex.l0:303 and :326; `tests/check/eof_digit` and
  `eof_float`), and a declaration whose parens do not balance is now
  reported at the declaration with the count and a guess at the line
  (`DParens` in parse.l0, rendered in main.l0; `tests/check/parens_*`).
- 2026-10-30: step 1 done: spec 2.4, 4, 5.8, 6.5, 7, 10.3; the changelog
  entry; the lexer's `TField`, the parser's named constructors, `EField`,
  and `EWith`, the checker's rules, the emitter's `l0_data_get` read and
  `l0_data_with` replacement, the runtime's `l0_data_with`;
  `tests/compiler/check_fields` (31 verdicts), `tests/unit/fields_test`,
  `tests/io/fields_in_place` (0, 1, and 100,000 copies for the three
  shapes). `tools/test.sh` 71 passed, `--compiled` 167 passed, `--virt`
  407 passed on both boards, fixpoint held, seed refreshed. Nothing uses a
  field yet. Next: step 2, the compiler, the kernel, the library, and the
  examples written with them.
