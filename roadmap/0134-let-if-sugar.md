# 0134: a let of several bindings, and an if of several tests

Kind: language
Status: done
Needs: 0132

## Why

Nesting is what makes closers hard to count: a chain of six `let`s or six
`if`s closes with seven parens, and runs of 9 to 19 end about 50 lines of
the compiler and the kernel, whose nesting reaches 15 to 19. Two sugar
forms cut the depth without changing what is said: `(let (a 1 b 2 c 3)
body)` for `(let a 1 (let b 2 (let c 3 body)))`, and `(if c1 e1 c2 e2
else)` for `(if c1 e1 (if c2 e2 else))`. Both desugar in the parser, so the
checker, the emitter, the runtime, and the seed's interface do not change,
and the existing forms stay valid. The smallest program that could not be
written: three bindings and a body closed with two parens.

```
(def f ((x int)) int
  (let (a (add x 1) b (mul a 2) c (sub b 3))
    (add a (add b c))))
```

The checker, before this item: `expected a name after let`.

## Done when

- the checklist in the l0-bootstrap skill
- spec 5, 5.2, 5.3, and 8 state the forms; the changelog says why
- `tests/compiler/check_sugar` holds the parser's and checker's verdicts,
  and `tests/unit/sugar_test.l0` the behaviour, scope among it
- the compiler and the prelude use neither until the seed that compiles
  them is refreshed and committed, by the two-step rule

## Log

- 2026-10-30: opened, from the review's plan. The spec written while
  0132's step 2 and 0133 ran their suites.
- 2026-10-30: done, changelog "A let of several bindings, and an if of
  several tests". `parse_if` collects its operands and nests them;
  `parse_let` takes a binding list; `parse_operands` is `parse_args` with
  its own unclosed message. `tests/compiler/check_sugar` (16 verdicts),
  `tests/unit/sugar_test` (5 tests, a million-step tail chain among them);
  `parse_errors` re-blessed for the new `if` message. The compiler and the
  prelude use neither form yet; the seed refreshed with this item compiles
  them, so a later change may. `l0 fmt` fixed the miscount in
  `check_sugar.l0` itself, its first use on a mistake.
