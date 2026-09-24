# calc

An interactive integer calculator. It prompts `> `, reads a line, prints the
value or an error, and repeats until end of input, when it prints a newline
and exits 0.

```
$ calc
> 2 * (3 + 4)
14
> 1 / 0
error: division by zero
> 9223372036854775807 + 1
error: overflow
> 
```

It supports `+ - * / %` and parentheses, with the usual precedence, left
associativity, and unary `-` and `+`. `/` and `%` truncate toward zero, as
L0's `div` and `mod` do. Values are 64-bit, and any result that does not fit
is an error rather than wrapping. A blank line prints nothing. Errors go to
stdout, so that they interleave with the prompts in a transcript.

## Files

- `calc.l0`: the lexer, checked arithmetic, recursive-descent parser, and
  `answer`, which maps one line to what calc prints for it
- `main.l0`: the prompt loop
- `calc_test.l0`: 18 tests, including overflow edges and a property test of
  `checked_mul` over 1,000 products that straddle 2^63
- `reference.py`: an independent evaluator in Python, for comparing on large
  inputs

## Status: done

- `l0 test`: 18 of 18 pass.
- Output matches `reference.py` on 200,000 generated lines, 1,810 of them
  divisions by zero. The comparison ignores error wording.
- Run in a pseudo-terminal, `> ` appears before calc waits for input, the
  answer follows each line, and Ctrl-D ends it with status 0.
- `L0_RC_CHECK=1` reports nothing live after the 200,000 lines.

## Measurements

200,000 lines of about 17 bytes: 0.99 s, 1.6 MB peak. Memory stays flat as
the number of lines grows, because the prompt loop is a tail call.

## Workarounds, named

- **Overflow is detected by hand (limit 04).** 38 lines of sign analysis in
  `checked_add` through `checked_mod`, and 37 lines of property test to trust
  them, because L0 arithmetic wraps silently and there are no bitwise
  operators. The literal lexer carries the same check.
- **`rev_toks` duplicates the prelude's `rev` for `(list Tok)` (limit 03).**
  4 lines.
- **Errors are forwarded by hand (limit 05, minor).** 8 match arms whose only
  job is to return the error they were given.

## Not supported

`-9223372036854775808` cannot be typed directly, because `9223372036854775808`
is too large to lex before it is negated. `-9223372036854775807 - 1` works.
