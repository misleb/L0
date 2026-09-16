# The L0 Programming Language — Seed Specification

L0 is a small, pure, statically typed language. This document is the complete
specification. There is no other documentation and no existing code to copy
from.

## Types

There are exactly three types:

- `int` — arbitrary-precision signed integer
- `bool` — `true` or `false`
- `list` — an immutable, possibly empty sequence of `int` (lists of lists do
  not exist)

## Grammar

```
program ::= decl+

decl    ::= "(" "def" name "(" param* ")" type expr ")"
param   ::= "(" name type ")"
type    ::= "int" | "bool" | "list"

expr    ::= integer                       // literal, e.g. 0, 7, -3
          | "true" | "false"              // bool literal
          | name                          // variable reference
          | "(" "if" expr expr expr ")"   // condition, then, else
          | "(" "let" name expr expr ")"  // bind name to expr, then body
          | "(" name expr* ")"            // call a builtin or a def
```

A `name` matches `[A-Za-z_][A-Za-z0-9_]*`, except that these five words are
reserved and may not be used as the name of a function, parameter, or `let`
binding:

    def   if   let   true   false

Whitespace and newlines are insignificant. A `;` begins a comment that runs to
end of line.

## Builtins

Each builtin is called like any other function: `(add 1 2)`. Arities are fixed.

| Builtin | Arity | Type | Meaning |
| --- | --- | --- | --- |
| `add` `sub` `mul` | 2 | int, int -> int | arithmetic |
| `div` `mod` | 2 | int, int -> int | truncating toward zero; error if divisor is 0 |
| `neg` | 1 | int -> int | negation |
| `lt` `le` `gt` `ge` | 2 | int, int -> bool | comparison |
| `eq` | 2 | int, int -> bool | equality |
| `and` `or` | 2 | bool, bool -> bool | strict: both arguments are always evaluated |
| `not` | 1 | bool -> bool | negation |
| `nil` | 0 | -> list | the empty list |
| `cons` | 2 | int, list -> list | prepend an element to the front |
| `head` | 1 | list -> int | first element; error on the empty list |
| `tail` | 1 | list -> list | all but the first element; error on the empty list |
| `is_empty` | 1 | list -> bool | whether the list has no elements |

Because `nil` takes no arguments, it is still written as a call: `(nil)`.

## Rules

- There are no loops. Iteration is expressed with recursion.
- Functions may be recursive and may call each other. The order of definitions
  does not matter.
- You may define as many extra helper functions as you like, with any names.
- The condition of an `if` must be a `bool`. There is no truthiness.
- A function's arguments and return value must match its declared types.
- Every function body is a single expression. There are no statements.

## Worked examples

The larger of two integers:

```
(def max2 ((a int) (b int)) int
  (if (gt a b) a b))
```

The number of elements in a list, showing recursion over a list:

```
(def length ((xs list)) int
  (if (is_empty xs)
      0
      (add 1 (length (tail xs)))))
```

The list `1, 2, ..., n`, showing a helper function with an accumulator, `let`,
and list construction:

```
(def upto_from ((i int) (acc list)) list
  (if (lt i 1)
      acc
      (upto_from (sub i 1) (cons i acc))))

(def upto ((n int)) list
  (let start (nil)
    (upto_from n start)))
```

The accumulator is built back-to-front: `cons` prepends, so counting `i`
downward from `n` produces a list in ascending order.
