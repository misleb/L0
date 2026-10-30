# 0145: the compiler's own structure

Kind: tooling
Status: proposed
Needs: 0135 for the first item

## Why

The review of the compiler found work it does several times or the slow
way, none of it visible to a program:

- environments are association lists searched linearly at every name
  (`find_sig` over about 730 signatures per call; `find_bind`,
  `find_ctor`, `find_data`, `lookup_operand`, `lookup_type`,
  `lookup_read_only`), while the prelude ships a `(Map K V)` and
  `lib/AGENTS.md` tells users never to write their own lookup
- a builtin's facts are spread over eight tables in two files (names,
  arity, argument types, result type, runtime symbol, borrowing,
  declares), each re-splitting a string literal on every call;
  `emit_op_plain` evaluates `(index_of n (rt_names 0))` twice per builtin
- expression types are computed three times: `check_expr`, `mono_expr`,
  and the emitter, because the checker hands nothing on
- free variables are recomputed at every `let`, `if`, and `match` arm, so
  a let chain costs its depth squared (`emit_let`, `emit_if`,
  `emit_match_arm`)
- `Diag`s are suppressed by matching message text (`known_only`), so
  rewording "unknown function" would break recovery silently
- metadata kept in names: `"'s "` for type parameters, `.` for copies, a
  pseudo-call named `"array.take"`

Self-compile is 0.58 s, so none of this is urgent; it is what the next
feature trips over. Each is a contained change in one file.

## Done when

- each item above is done or recorded as not worth it, one bootstrapped
  change at a time, the fixpoint and both suites green after each
- self-compile time and the seed's size recorded before and after in the
  changelog, as every performance change has been
- 0135 first for the lookups, since it removes six of the seven

## Log

- 2026-10-30: opened, from the review (its item 3.1); proposed.
