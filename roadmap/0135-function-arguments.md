# 0135: functions as arguments, by copies

Kind: language
Status: proposed
Needs: 0132

## Why

A function cannot be passed to another, so every loop that differs only in
what it does to each element is written out again. The compiler has seven
copies of one lookup, `find_bind`, `find_sig`, `find_ctor`, and `find_data`
in check.l0 and `lookup_operand`, `lookup_type`, and `lookup_read_only` in
emit.l0; seven full walks over the eleven-constructor `Expr`, since there
is no fold; and `l0 test` finds a program's tests with `sed` and writes a
`main` that dispatches on their names, because a test cannot be passed as
a value (tools/l0, the `test` command). The library's `sort`, `min`, and
`max` serve every type only because `compare` was made a builtin; sorting
by a key still means declaring a key type. The smallest program that
cannot be written: a lookup by a key function, once.

```
(def (find_by K T) ((key (fn (T) K)) (k K) (xs (list T))) (Option T)
  (if (is_empty xs)
      ((None T))
      (if (eq (key (head xs)) k) (Some (head xs)) (find_by key k (tail xs)))))
```

The checker, before this item: `expected list, array, or a data type name
after ( in a type` at `(fn`.

## The route, as the review sketched it

The changelog rejected function values four times, for needing indirect
calls, an exception to section 8's tail-call guarantee, a wrapper per
function, and no argument to take a generic callee's types from (the
entries for `compare`, 0059 and 0064, and for handles, 0020). Every one of
those follows from making functions runtime values. Make them compile-time
values instead:

- a parameter may have a function type, `(fn (T1 ... Tn) R)`; an argument
  in that position must be the name of a `def` or a builtin, never a
  parameter or a `let` binding, so there are no closures and nothing to
  keep a function's environment in
- the compiler emits one copy of the callee per distinct function argument,
  named for it, exactly as 10.2 emits one copy per kind of type parameter,
  so within a copy every call through the parameter is a direct call of
  the named function: `fastcc`, `musttail`, read-only parameters, and the
  release rule are untouched, every value is still an `i64`, and no
  function pointer exists at run time
- name resolution stays syntactic: a lower name in call position resolves
  to a `def`, then a builtin, then a function-typed parameter of the
  enclosing `def`; a program with no function-typed parameter resolves as
  it does today, so nothing existing changes meaning
- the set of copies is finite, since only top-level names can be passed;
  a copy's name has a dot, as a kind copy's does, which no source name has
- a generic function passed as an argument takes its types from the
  function type it is passed at, which the call site fixes, so the "no
  argument to take its types from" objection does not arise

What it does not give: closures. A comparison that reads data outside its
arguments, 0028's sort of lines by index into one buffer, still passes the
buffer alongside, which a function parameter with one more argument
expresses.

## Open before it starts

- the written form of a function type, and whether a `def` with type
  parameters may be passed at a type that fixes some of them
- whether a function-typed parameter may be passed on to another function
  (it can, as a copy of a copy; the question is whether to say so first
  or to start with calls only)
- the copy count: a function taking two function parameters, each given
  three functions across the program, is nine copies; measure on the
  compiler once its lookups are rewritten
- the two-step rule applies twice: the compiler compiles the feature, the
  seed is refreshed, then the compiler's seven lookups and seven walks are
  rewritten with it, which is the measurement of whether it earned its
  place, and then `l0 test` may stop writing a `main`

## Done when

- the checklist in the l0-bootstrap skill
- spec 3, 4.1, 5.7, 7, and 10.2 state the rule; the changelog says why,
  and answers the four rejections above by name
- `tests/compiler/check_fn_args` holds the checker's verdicts and
  `tests/unit/fn_args_test.l0` the behaviour, a tail call through a
  function parameter among it
- after the seed is refreshed: the compiler's seven lookups are one, and
  its seven `Expr` walks share a fold where that reads better

## Log

- 2026-10-30: opened, from the review (its item 1.2), after 0132 to 0134
  landed; proposed, not started, at the user's request.
