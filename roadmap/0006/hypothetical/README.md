# HYPOTHETICAL code: what should have been possible

Nothing in this directory is L0. Each file is the code I would have written
for a limit in `../limits/` if L0 had the facilities below. None of it checks.
[`../check.txt`](../check.txt) records what `tools/l0check` says about each
file: each fails only on a missing facility, never on anything else. The
checker reports one error per declaration, so each declaration shows only
its first missing facility.

File numbers match the limits: `NN-*.l0` here is the code that
`../limits/NN-*.l0` blocks.

## The facilities these files assume

This is one consistent set, chosen as the smallest one that all seven files
could share. It is a record of what the code wanted, not a proposal. The
README one level up discusses the design.

| Assumed | Type | Meaning |
| --- | --- | --- |
| `main` declared as `(def main ((args (list (list int)))) int)` | | `args` is argv, program name first. stdin is **not** pre-read. The result is the exit status. |
| `(read_line)` | `-> (list int)` | The next line of stdin, including its `\n`. The last line may lack one. Empty **only** at end of input, so an empty line (`"\n"`) and end of input are different values without a new type. |
| `(write_stdout bytes)` | `(list int) -> int` | Writes now, in evaluation order. Buffered, but flushed before any read and at exit, so a question is visible before its answer is read. Returns the byte count. |
| `(write_stderr bytes)` | `(list int) -> int` | Same, to stderr, unbuffered. |
| `(open_read path)`, `(open_write path)` | `(list int) -> Opened` | `(data Opened (Opened File) (OpenFailed (list int)))`, with `File` an opaque type. `OpenFailed` carries the reason, such as `No such file or directory`. |
| `(read_bytes f max)` | `File, int -> (list int)` | Up to `max` bytes; empty only at end of file. |
| `(write_bytes f bytes)` | `File, (list int) -> int` | Byte count, or negative on error. |
| `(close f)` | `File -> int` | 0, or negative on error. |
| Reclamation | none | A cell no longer reachable is freed. This needs no syntax, so file 02 contains the same `bump` as `../counter/counter.l0`, unchanged. |

Effects are sequenced with `let`, relying on section 8's left-to-right strict
evaluation, which is already specified. A binding such as `(let w
(write_stdout ...) rest)` exists only to put the write before `rest`.
