# filecopy: `./filecopy in.txt out.txt`

**Status: blocked at the first step. There is no L0 program here.** The only
program L0 could run is `main` returning its input, which copies stdin to
stdout. That is `cat`, not filecopy, and writing it would hide exactly what
is missing.

| File | What it is |
| --- | --- |
| `in.txt` | the test input the program would copy |

filecopy needs three things L0 does not have. Each has a limit program, and
the exact output is in [`../check.txt`](../check.txt):

1. **The command line.** [limits/05](../limits/05-no-command-line.l0): a `main`
   that takes `args`. Section 9 allows only `(main input)`.

   ```
   $ tools/l0 build programs/limits/05-no-command-line.l0
   error: main must take one parameter of type (list int)
   ```

   `tools/l0check` prints `ok` for this file. The top-level README explains
   why.

2. **Files.** [limits/06](../limits/06-no-files.l0): no builtin names a file.

   ```
   programs/limits/06-no-files.l0:10:4: error: unknown function 'read_file'
   programs/limits/06-no-files.l0:13:4: error: unknown function 'write_file'
   ```

3. **Reporting failure.** When `in.txt` is missing, filecopy must say so on
   stderr and exit nonzero. [limits/07](../limits/07-no-failure-report.l0):

   ```
   programs/limits/07-no-failure-report.l0:11:4: error: unknown function 'fail'
   ```

   The only nonzero exit is a runtime error.
   [limits/07b](../limits/07b-only-exit-is-a-crash.l0) checks and runs: exit
   70, empty stdout, and stderr `l0: runtime error: head of empty list`. The
   program cannot choose the status or the message.

Even with all three, copying a large file through the current host would cost
16 bytes of memory per file byte, because the bytes arrive as a
`(list int)`. [Limit 01](../limits/01-input-read-whole.l0) measures that.
Doing it in constant memory also needs chunked reads and writes and
reclamation.

The code that should have been possible, with every failure reported:
[hypothetical/06](../hypothetical/06-no-files.l0).
