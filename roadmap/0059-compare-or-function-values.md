# 0059: research: ordering a value of any type, by `compare` or by function values

Kind: research
Status: done; a structural `compare` first (0064), then the library's
sort, min, and max over it (0065); function values wait
Needs: nothing

## Why

[0055](0055-programs-round-three.md)'s structures worker could not write a
heap or a balanced tree once for every element type:

```
(def (smaller T) ((a T) (b T)) T
  (if (lt a b) a b))
```

```
$ tools/l0 check tmp/0055/structures/limits/01-order-type-param.l0
tmp/0055/structures/limits/01-order-type-param.l0:9:7: error: an argument of lt must be int, but this is T
```

Passing the order instead fails too (`limits/02`): `error: int_less is a
function, and L0 has no function values`. The named workaround orders a
closed sum `Key = KInt int | KStr bytes`, which costs 5.2 times on the heap
and 1.2 on the set, and admits no record as an element. The numbers worker
passed operations as int codes for want of function values. A persistent
ordered map, which 0055's editor wrote by hand as a 185-line AVL tree,
needs one or the other.

## The question

Which comes first, and at what cost to the properties the `l0-bootstrap`
skill lists? Weigh at least:

- a structural `compare` builtin on any type, as `eq` and `hash` are, with
  its order specified: what it does on lists, bytes, arrays, and data
  values, and whether a structural order is the one programs want (0041
  found most orders written here are not structural)
- a function type and function values: syntax, checking, and what a
  function value is in memory, given reference counting, tail calls, and
  padded arities (spec 8, 10)
- both, and which one the other would later make redundant
- the code here that each would change, counted: 0055's heap, set, and
  editor; the compiler's own sorts and orders; the library's helpers

## Done when

- the Log has a finding: each candidate's semantics, implementation, and
  cost, with 0055's programs rewritten against each in a prototype where
  that can be done without the feature
- a recommendation that names the first language item, with a program from
  this repository as its Why, and the items after it in order

## Log

- 2026-10-06: opened by 0055, with the user's agreement.
- 2026-10-07: **finding.** A read-only worker inventoried every ordering in
  `compiler/`, `lib/`, `tests/`, and the programs of 0014, 0028, 0055, and
  0062; the two FUNCTION rows and a KEY row were re-read in the main tree.
  - **Inventory: 21 orderings in real code**, besides hypotheticals and
    limits. The compiler and the library sort nothing; they take an int
    max in two places.
    - **11 STRUCTURAL**, a structural order gives them directly: 0014's
      wordfreq tree of words, 0028's insertion sort of lines in a test,
      three Dijkstra heaps of (distance, node) and 0028's three layouts of
      one, 0055's `Key` (whose `key_cmp` *is* the structural order on
      `Key`) and its int heap and set, `parametric_data`'s `(Tree int)`,
      about 15 int min and max one-liners in 13 files, and the compiler's
      `file_at`
    - **8 KEY**, structural once the program builds a key: wordfreq's count
      descending then word, `(K (neg count) word)`, twice; Kruskal's edges
      by weight, `(Pair w i)`; sudoku's fewest candidates; editdist's best
      split; `mst_test`'s (weight, node), which today packs both into one
      int as `w*n + b`, and can overflow; `index_of_max`; and 0055's
      bignums, whose limbs are least significant first, so their key is
      `(NK (length a) (rev a))`, and a direct structural compare would be
      wrong
    - **2 FUNCTION**: 0028's line sort (`sort/sort.l0:63`, checked) and its
      copy over another buffer, whose order is bytes of a slice of one
      shared buffer, by line index. A key would copy every line, which the
      program was written to avoid. Note that **function values without
      closures do not serve these either**: the comparator reads `b` and
      `st`, so it needs them captured or passed as a context argument
    - **Operations passed as int codes or flags** for want of function
      values: 0055's calculator (two functions per operation), 0014's
      calculator, base64's test modes, kmerge's `numeric` flag through five
      functions, sudoku's and life's modes, and four places code was written
      twice. Each is a few lines of `if`; none is an order
  - **`compare`.** `(compare a b)` gives -1, 0, or 1, for `a` of any type
    and `b` of the same, as `eq` does, with the order specified in the
    spec: ints by value, signed; `false` before `true`; lists, bytes, and
    arrays lexicographically, element by element, a proper prefix first
    (one rule for all three, rather than the length-first rule
    `heap_compare.l0` sketched for arrays, which no program orders); data
    values by their constructor's position in the declaration, then field
    by field. It agrees with `eq`: 0 exactly when `eq` is true. Checking is
    `eq`'s rule, so no unification and no inference; on `int` and `bool` it
    is two `icmp`s and a `select`, on anything counted a call of a runtime
    walk like `@l0_hash`'s, which visits in order with a worklist of its
    own, so no stack. Cost, by 0042's measure: one language item, a
    runtime function, a section of the spec, and one declare in every
    module. It buys 0055's heap and set written once, records included,
    with `Key` and its boxing gone (5.2 times on the heap), and every KEY
    row with a key data type of two or three fields
  - **Function values.** A function type, a name in value position, a call
    through a local, a wrapper per function used as a value (since a
    function's prototype is padded to its tail-call component), owned
    arguments at the wrapper (since a caller cannot know which parameters
    the callee borrows), and an exception to section 8, since an indirect
    call cannot share every caller's prototype and so cannot be `musttail`.
    A generic function passed as a value has no argument to take its types
    from, against the no-inference property. Without closures the two
    FUNCTION rows still need a context argument threaded by hand. Several
    items, and spec sections 3, 5, 7, 8, and 10
  - **Recommendation.**
    1. [0064](0064-compare.md), language: `compare` on any type, with
       0055's `limits/01-order-type-param.l0` as its Why. The compiler and
       the prelude use none of it, and the seed is refreshed
    2. [0065](0065-library-on-compare.md), tooling: the prelude's generic
       `sort`, `min`, and `max` over `compare`, a separate step since the
       prelude is compiler source; the examples and both skills say how to
       order by a key, and that a structural order is not a numeric one for
       a representation like the bignums'
    3. function values wait. What would earn them is a program whose order
       no key can express without copying, as 0028's line sort, or whose
       operations are chosen at run time often enough that the int codes
       cost something; and when they come, closures or a context argument
       must come with them, or they do not serve the code that asked
