# 0032: Bytes held one byte per byte

Kind: language
Status: queued, needs 0031
Needs: 0031

## Why

From [0028](0028-programs-with-arrays.md), measured by
[0026](0026-packed-bytes.md)'s prototype: json and sort hold their input as
an array and peak at 25 bytes a byte, 257 MB for 11.5 MB of JSON and 260 MB
for 10 MB of lines (`0028/text/limits/01-input-into-array.l0`). An input
builtin reading into an `(array int)` of the right size only gets to 9, since
an int array costs 8 bytes a byte. The prototype's packed type gets json to
13.6 MB and sort to 17.6 MB and 0.08 s from 0.25 s; the programs are in
`0026/bench/stage2/`, and 0026's Log has the full table and design.

## Done when

The l0-bootstrap checklist, starting from the prototype on branch
`proto/packed-bytes` (its compiler and runtime diff; not its seed, which is
regenerated), and settling in the spec:

- the builtins' names, chosen for what they do now that 0031 lets a builtin
  share a name with a program's function; the prototype's six operations
  (read all of a handle, length, byte at, from a list, to a list, write a
  range) and no more unless a program needs one
- whether `bytes` is reserved like `int`, `bool`, `list`, and `array`, or
  recognized only where a type is expected; the prototype chose the second,
  because the wordfreq test names a parameter `bytes`, which would make it
  the first lower type name that is not reserved
- spec 10.3's rule that a borrowing builtin's pointer result gains a
  reference, which holds only for a result taken from the argument; a
  builtin that returns a new block consumes its argument instead
- the layout in 10.1: an array's header and length word, then the bytes
- the parse message "expected a type: int, bool, (list T), or (array T)",
  which the prototype left without `bytes`

Tests in the compiled suite only, since stage 0 cannot run the type, as with
arrays, including a range error, a read failure seen through `read_from`
after reading all, and `L0_RC_CHECK` clean on 0026's json and sort inputs.

## Log

- 2026-09-29: opened from 0026's finding.
