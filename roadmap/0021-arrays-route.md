# 0021: How L0 gets arrays, compact bytes, and in-place update

Kind: research
Status: done; language items 0023 and 0024 queued, 0025 and 0026 proposed
Needs: 0020

## Why

The next goal, by the user's choice from [0014](0014-programs-round-two.md)'s
evidence. All three workers hit the lack of an indexed table, and it cost
more than anything else they hit:

- `0014/text-tools/limits/01-no-array.l0`: a byte histogram of 1 MB takes
  1.48 s as a list of counts and 0.33 s as a depth-8 tree, re-checked in the
  main tree; reading the bytes alone is a small fraction of either. wordfreq
  is 9 times slower than Python, a third of it rebuilding tree paths to add 1.
- `0014/data-structures/limits/01-no-indexed-table.l0`: Dijkstra over a
  persistent trie is 3 times slower than CPython, with 61% of a query in
  reference counting on nodes only being read. Checker output:
  `expected list after ( in a type`, and `unknown function array_new`.
- `0014/bytes-encodings/limits/03-no-arrays.l0`: Myers' diff at D = 10,000
  takes 1.40 s rebuilding its vector, against 0.02 s over a C array.

Two workers also hit bytes held as cons cells, 24 bytes each: holding 10 MB
of input peaks at 242 MB, re-checked, and building lines is half of
minigrep's time (`0014/data-structures/limits/04`, `0014/bytes-encodings/limits/02`).

The workers' hypotheticals all want an array whose update happens in place
when nothing else holds it. Under today's release rule a loop's own
reference is still held when the update runs, so that needs a value released
at its last use: [0013](0013-release-at-last-use.md)'s rule, dropped then for
lack of a use, and this would be one.

## Done when

A written finding that settles, with measurements: the type and builtins, how
an array is laid out and counted, whether bytes are a separate packed type
or an array of `int`, the release rule in-place update needs, what each
costs the properties the l0-bootstrap skill lists, and the language items it
breaks into, each one bootstrapped change.

## Log

- 2026-09-24: opened from 0014, after the I/O gaps 0018 to 0020.
- 2026-09-25: active. Design analysis before measuring, from the runtime,
  the emitter, and 0014's hypotheticals:
  - **Type.** Every hypothetical wants `(array T)` with element types `int`,
    `(list int)`, and `(list Edge)`, so an int-only array would not serve.
    It would be the second parametric type constructor, which the
    l0-bootstrap skill lists as a property; what that property buys, no
    unification, survives, since an array's element type is determined by
    an argument exactly as a list's is (`array_new n x` by `x`).
  - **Layout.** The header's size field is 8 bits and its mask 32, so an
    array cannot be described by them. Size 0 is never used (a cons cell is
    2 words, a data block at least 1), so it can mark an array: a length
    word, then the elements, with mask bit 0 meaning the elements are
    pointers. Arrays come from malloc and go back to free, since the free
    lists are by size and stop at 256 words.
  - **In-place update needs a new release rule.** Today a binding keeps its
    reference until its scope ends and every use adds one, and a match takes
    its fields before releasing a subject that the binding still holds. So
    in every hypothetical loop the array's count is 2 at `array_set`, and it
    would copy the whole array per update. The rule needed is 0013's, but
    stronger than the version 0013 built: release each binding at its last
    use on each path, through `if` and `match` (a binding a branch does not
    use is released as the branch starts), with a borrowing builtin reading
    a still-live variable without a reference at all.
  - **A trap in evaluation order.** In `(array_set counts b (add (array_get
    counts b) 1))`, left to right makes `array_get` the last use, so
    `array_set` would still copy. Taking variable operands after the others
    is unobservable, since section 8 lets an evaluation that can neither do
    I/O nor fail move, and it makes the natural form update in place.
  - **Bytes.** Arithmetic says a packed `bytes` is worth its own type: 1
    byte per byte, against 8 for `(array int)` and 24 for a list; 0014's
    json held 11.5 MB of input in 276 MB.

  Measuring needs a prototype of arrays and the rule, which changes the
  compiler and runtime, so it goes to a worker in its own worktree and branch,
  not merged. Next: its report, then the finding.
- 2026-09-25: **finding.** The prototype is branch
  `proto/arrays-release-at-last-use`, four commits on `3343d18`: arrays under
  the current rule, then release at last use, both bootstrapped to a
  fixpoint with both suites green on macOS and Linux and nothing live under
  `L0_RC_CHECK`, including the compiler compiling itself. Its benchmark
  sources are kept in `0021/bench/`. Measured by the worker on an M4 Pro,
  mean of 5 after a warm-up; the coordinator rebuilt the array benchmarks
  from the branch and re-ran the headline rows and the copy counts, which
  agree:

  | | lists or trie, today | arrays, today's rule | arrays, last-use rule |
  |---|---|---|---|
  | histogram of 1 MB | 1.26 s list, 0.18 s tree | 0.050 s, 1,051,800 copies | 0.012 s, 0 copies |
  | Myers at D = 10,000 | 1.37 s | 76.6 s, 50,005,000 copies | 0.156 s, 0 copies |
  | Dijkstra, per query | 31.3 ms | 51.2 ms, copying | 8.7 ms, 0 copies (CPython 10.7) |
  | compiler on itself | 0.26 s, 27.3 MB | | 0.15 s, 20.6 MB, IR 15% smaller |

  What this settles:
  - **The release rule comes first, and alone.** Arrays under today's rule
    are much slower than the lists they replace, because every update in a
    loop copies (Myers: 77 s against 1.37 s). With the rule every
    benchmark loop updates in place. The rule also pays for itself before
    any array exists: the compiler runs 42% faster and holds a quarter less
    on its own source, with two thirds fewer increments and releases. The
    rule is: each pointer binding is released at its last use on each path;
    a branch releases what only other branches use as it starts; a borrowing
    builtin or a match reads a still-live variable with no reference at all;
    a call takes its variable operands after the others; a parameter or let
    never used is released at once. The prototype carries a `live` set
    through the single-pass emitter, costing about 3% of compile time, and
    removes `release_all`: in tail position everything has already gone.
    Whether a loop updates in place depends on this rule and on the operand
    order, so the spec must state both as guarantees, as it does tail calls,
    and not as freedoms. That is 0023.
  - **Arrays: `(array T)`,** with `array_new`, `array_len`, `array_get`, and
    `array_set`, `array_set` updating in place when its array's count is 1
    and copying otherwise. An index out of range and a negative length are
    runtime errors, growing section 8's list. A header size of 0 marks an
    array: a length word, then the elements, mask bit 0 meaning they are
    pointers, from malloc and back to free. `array` becomes a reserved word
    as `list` is. It costs one listed property, that `list` is the only
    parametric type constructor; no unification is needed, since elements
    are typed by arguments as a list's are. Match, inference, and function
    values are untouched, and no mutation is observable, so the no-cycles
    argument reference counting rests on still holds. That is 0024.
  - **Nested update copies.** In `(array (array int))`, `array_get` must
    give the row its own reference, so updating a row copies it every time
    (`0021/bench/scratch/grid.l0`: 10,000 copies for 10,000 updates). The
    workaround swaps a placeholder in first. A builtin that takes an element
    out would need to return two values, and without type parameters there
    is no pair to return them in. Open, as 0025, until a program needs it.
  - **Bytes stay out for now.** Holding 10 MB takes 242 MB as a list and 82
    MB as an `(array int)`, measured, so arrays alone cut 0014's worst
    memory case by three; a packed type would cut it to about 11 MB. That
    is 0026, to be earned by a program that `(array int)` still fails,
    since arrays may change what the json and minigrep workers would write.
    Building an array from a list peaks at both at once, since freed cells
    stay on the free lists, so reading input straight into an array belongs
    with it.
  - **The spec needs, besides the above:** section 10.3's ownership bullets
    and "freed no later than the end of the scope" rewritten for the rule
    (0023); section 10.1's layout for arrays (0024); and a note that a count
    stuck at its maximum is reachable by `array_new` of 2^24 copies of one
    pointer, which then is never freed (0024).
