# 0048: tooling: the examples show what L0 has gained since they were written

Kind: tooling
Status: done
Needs: nothing

## Why

`lib/examples.l0` is what `l0 examples` gives every agent outside this
repository, and the `l0-code` skills tell agents to read it before writing
anything substantial. It is accurate, but it predates several features that
change how ordinary code is written:

- write failures (0018): `first_line_of` closes a file without looking at
  what `file_close` returns, the only place a failed write shows
- appending and replacing a file in one step (0019), and files in memory
  for testing I/O code on a string (0020), appear nowhere in it
- `next_line` (0017): `count_lines` uses `read_line`, which cannot tell a
  failed read from the end of input
- a grid kept as an array of rows (0025) updates a cell in place only when
  written in the one form spec 6.5 gives, which no example shows
- growing an array with `array_resize`, and timing a phase with `clock_ns`
  (0034)
- `is_vowel` is the `or` chain the skill says to replace with `any_eq`,
  which works on a string's bytes now that it is generic

## Done when

- each of the above has an example in `lib/examples.l0`, said in its
  comment, and a test in `lib/examples_test.l0`, none of which writes a
  file, since `l0 test $(l0 examples --path)` runs wherever its user is
- `tools/l0check` passes on both, `l0 test` passes on them, and both suites
  are green

## Log

- 2026-10-05: opened at the user's request, after reviewing the examples
  against the spec.
- 2026-10-05: done. No language change, so no changelog entry.
  - `lib/examples.l0`: `is_vowel` is `(any_eq c "aeiou")`;
    `count_lines_in` reads an IoFile with `file_next_line` and handles
    `IoError`; `replace_file` writes under another name, checks
    `file_close`, and renames over; `log_line` appends with
    `open_appending`; a note on testing IoFile code in memory; `IntStack`
    grows its array with `array_resize` by doubling; `grid_set` and
    `grid_get` show the one in-place form for an array of rows, and say
    that `array_new` of a row shares it until each row's first update;
    `vowel_count_ns` times a phase with `clock_ns`
  - `lib/examples_test.l0`: six tests. `test_stack` pushes 100,000
    elements, which would take far too long if the array copied on each
    push. The file tests check only failure, a missing directory, since
    `l0 test` runs wherever its user is and L0 cannot delete a file. That
    is spec 6.3's -5, "input or output failed": `open_write` and
    `open_append` never return -3. The success paths were run once by
    hand in a scratch directory: the file was replaced, no `.new` was
    left, and the log kept both lines
  - `lib/AGENTS.md` lists what the examples now cover
  - `l0 test` passes all 23 and writes nothing; both suites green (63,
    110)
