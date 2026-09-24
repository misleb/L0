# 0007: Checking enforces main's signature

Kind: language
Status: active
Needs: nothing

## Why

From [0006](0006-ordinary-programs.md), `0006/limits/05-no-command-line.l0`:

```
(def main ((args (list (list int))) (input (list int))) (list int)
  (head args))
```

`tools/l0check` and `tools/l0 check` print `ok` for it. `tools/l0 build`
rejects it, and its message has no file or line:

```
error: main must take one parameter of type (list int)
```

Checking passes `#nomain`, and section 9.1 says `#nomain` "relaxes nothing
else", but a present `main` with the wrong signature is not checked at all.
The rule to trust `l0check` makes this a trap: the 0006 worker nearly
recorded a blocked program as passing.

## The change

- `spec/L0.md` section 9.1: `#nomain` means a `main` need not exist; one that
  does must still satisfy section 9.
- `compiler/check.l0`: apply section 9's signature rule to a program `main`
  whenever one exists, and report it at `main`'s location.
- a stage test in `tests/compiler/` that feeds a `#nomain` bundle with a
  wrong `main`, and the new located message wherever the old one appears

## Done when

- the checklist in the `l0-bootstrap` skill
- `tools/l0check` rejects `0006/limits/05-no-command-line.l0` with a file and
  line

## Log

- 2026-09-23: opened from 0005's recommendation.
