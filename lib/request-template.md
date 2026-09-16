# Feature request: TITLE

Status: draft
Project: PROJECT

A request is judged against keeping L0 small, so evidence matters more than
argument. Every section below should be filled in; see the `l0-limits` skill
for how to decide whether a limitation is worth reporting at all.

## What could not be written

The L0 you wanted to write, and the error or the reason it is not legal.
Actual code, not a description of code.

```
```

## The workaround actually used

The code that shipped instead, with the file and line range so it can be
read in context. A request without a working workaround is premature: write
the code first, then report.

```
```

## What the workaround costs

Pick one and give the evidence for it.

- **Constant per use site.** Then this is probably not a request at all,
  unless the same workaround has appeared in three unrelated places, in
  which case list them.
- **Loses a correctness property.** Say exactly what stops being checked,
  and what would go wrong silently.
- **Grows with the program.** Say what makes it grow: how many places a new
  case has to touch, or why the work is superlinear.
- **The program cannot be written.** Say what is impossible, not merely
  awkward.

## Smallest change that would help

The least the language could gain and still solve this. Not a wishlist.
If a smaller version would solve most of the problem, propose that instead
and say what it leaves out.

## Which deliberate restriction this breaks

One of these, or none:

- one-level `match` patterns with no wildcard
- no type inference
- `list` as the only parametric type constructor
- no function values

Say what the restriction is currently buying and why this case outweighs it.

## Alternatives considered

Including the two that most requests turn out to be:

- a host-side protocol on the byte channel, for anything about input or
  output
- an ordinary function, or an addition to the prelude rather than to the
  language

Say why each was ruled out.
