# L0 specification changelog

Every change to the language is recorded here, with the reason it was made. The
spec itself ([L0.md](L0.md)) says only what L0 *is*; this file says why.

New entries go at the top.

---

## A program can learn that its writes failed

**L0 gains `flush`,** a builtin that delivers what a handle holds back,
leaves it open, and returns 0, or -5 if any byte written to it was lost, or
-2 if it is not open for writing (section 6.3). It works on standard output
and standard error, which `close` refuses. **A write failure no program was
told of is now a runtime error at exit,** status 70 whatever `main` returned,
where before it was silently ignored.

**The blocker.** Roadmap item 0014's base64, run with standard output closed,
wrote nothing, and exited 0: every `write_byte` returned 0 because it only
buffers, and `(close 1)` returned -2. `write_to` and `write_byte` only buffer,
`close` was the only thing that reported a write failure, and it refuses
handles 0 to 2, so no L0 program could find out. The system `base64` in the
same situation says "write error" and exits 1. `tests/io/write_failure` is
now that program's check, and it passes on macOS and Linux.

**Why a builtin, and not a result from `write_to`.** When a write fails
depends on how much the runtime holds back, which section 6.2 leaves to the
implementation, so a `write_to` that returned -5 would return it at a moment
the program cannot predict and another implementation would not reproduce.
`flush` makes the moment of the check the program's own. It is also what
`close` already did for a file, less the closing, which standard output
cannot afford: a filter checks once at the end and can still write to it.
The name is the one every other language uses. Like any new builtin it
takes the name from programs, since a builtin wins in call position; 0014's
wordfreq defined a `flush` of its own, which now has to be renamed.

**Why a failure sticks.** A lost byte stays lost, whatever succeeds after it,
so once a write to a handle fails every later `flush` and `close` of it
return -5. Otherwise a program would have to flush after every byte to know
that its output was whole. The runtime already kept this state per handle;
it only had no way to say so for handles 0 to 2.

**Why the host reports what the program never saw.** A `main` that takes its
input has its result written after it returns, so it could never check that
write, and the compiler is such a program: with standard output on a full
disk it would have left truncated IR and exited 0. Leaving the exit status
alone would have kept exactly the failure this entry is about for every
program that does not flush. So a failure is *reported* once a `flush` or
`close` of its handle returns -5, and one still unreported when the program
ends, including one the final delivery causes, is the runtime error of
section 8. It overrides any status, since the status was computed without
knowing, and a program that was told keeps the status it chose, so base64
can still exit 1 with its own message. Status 70 and the `l0: runtime error:`
line are what the runtime errors already use; the message is `write failed`,
and if standard error is what failed, the status alone says so.

Section 6.3 said nothing about what happens when delivering held-back bytes
at exit fails; it now does, and sections 6.2, 8, 9, and 10.3 say the same.

**The seed.** `@l0_flush` is appended to the runtime interface, and the
exit-time check is in the runtime alone, so programs built by an older seed
get it too. Stage 0 is frozen and does not know `flush`, so the tests are in
`tests/io`, with hand-written expectations; its own exit status on a lost
write is unchanged, which no test compares.

---

## The standard library documents itself

**What an agent reads about L0 now comes from the toolchain, not from
copies.** `l0 init` used to copy the specification, the examples, and the
library into each project, where they stayed as the toolchain moved on. Now
it copies only `AGENTS.md` and the `l0-code` skill, and `l0 spec`, `l0
examples`, and `l0 doc` show the installed ones.

**`l0 doc` reads the library's own comments.** A `;;` block directly above a
`def` or `data` is its documentation and makes it public; one without is
internal. `l0 doc` lists every public name with its signature and the first
sentence of its comment, and shows one file, one name, or a search in full.

**Why not skills, or the spec.** A skill describing the library is copied by
`l0 init` too, so it drifts just as the library copies did, and it is a
second record of every fact that nothing checks against the first. Library
details in `spec/L0.md` would make the language's definition grow with every
helper. Documentation next to the code is reviewed with the code, and a test
pins the index, so a change to the library's surface cannot go unnoticed.

This is not a language change. `;;` is an ordinary comment to the compiler.

---

## Reading a line can report a failure, and no language change for it

**`lib/io.l0` gains `next_line` and `file_next_line`,** which return an
`IoLine`: `(IoLine s)`, `(IoEnd)`, or `(IoError code)`. All three of roadmap
item 0014's workers found that `read_line` and `file_read_line` treat a
failed read as end of input, so a failed read looked like a short file,
which the skill tells a program never to allow. linediff, minigrep, and
kvstore each wrote their own reader. Two of their hypotheticals proposed this
same type, one with a code and one with words; it carries the code, because
kvstore had to match on the text of `IoFailed`'s words to tell a missing
file from others, and `io_error` still gives the words.

`read_line` and `file_read_line` stay as they were, since most programs
reading standard input only want the lines, and now say in their comments
that a failure ends a line.

**The prelude's `length` and `append` no longer take a stack frame per
element,** nor does `lib/io.l0`'s `args`. `length` of 10 million elements
used 320 MB of stack. `append` now reverses its first list and reverses that
onto the second: twice the copying, for no measured change in the compiler's
time, since it only ever appends short strings.

None of this is a language change: no rule in `spec/L0.md` changed, and the
prelude remains ordinary L0. It is recorded here because the prelude is what
every program links, and because the choice between an `IoLine` type and a
second return value is one a later reader would otherwise have to guess.

---

## A tail call uses no stack

**Every tail call is now guaranteed** (section 8). Section 8 defines tail
position and tail calls, and a chain of tail calls of any length, between
functions of any arities, runs in the stack of one activation. Before, it
left the outcome unspecified, and the outcome depended on the host: the
optimization level, whether LLVM inlined the functions involved, and how
many arguments the target passes in registers. That was the question roadmap
item 0011 researched; its measurements are in `roadmap/0011/`.

**The blocker.** L0 has no loops, so every loop is recursion, and a state
machine written as mutually recursive functions is ordinary L0. Measured
with an 8 MB stack before this change:

```
self-recursive loop, -O0                        exhausted at 1 million
tail calls between a 10- and a 2-argument
  function, -O2, neither inlined                exhausted at 1 million
```

The second is the default build of a program large enough that LLVM does
not inline its loops, and a call between functions of seven and two
arguments behaved differently on arm64 and x86-64. So the same program could
run on one machine and exhaust the stack on another. The compiler itself,
built at `-O0`, needed a 128 MB stack to compile itself.

**How.** A tail call is emitted as `musttail call` followed by `ret`, and an
`if` or `match` in tail position returns from each branch instead of joining
(10.3). `musttail` makes LLVM keep the guarantee at every optimization level
or refuse to compile, so a toolchain that cannot honor it fails at build
time, never at run time. It requires caller and callee to have the same
prototype, so a function takes as many parameters as the widest function in
its tail-call component, padded with zeros (10.2). The program's `main` is
wrapped, because the runtime calls every `main` with one argument.

**Why this way.** 0011 compared five implementations by rewriting the IR the
compiler emitted:

- `tailcc`, LLVM's convention for guaranteed tail calls, needs no padding, but
  LLVM rejects it for RISC-V, 32-bit ARM at `-O0`, and wasm. Section 10 makes
  the output the same bytes on every host, so the compiler cannot choose it
  per target.
- `musttail` with the C convention and no padding fails at once: the prelude
  itself tail-calls across arities.
- Padding every function to the module's widest costs 13% more code at `-O0`,
  and one wide function makes every call pay for it. Padding per component
  pads only what needs it.
- Turning self tail calls into loops in the emitter is portable, but covers
  200 of the compiler's 314 tail calls and none that are mutual.

**Measured after**, all on an 8 MB stack unless stated:

```
the eight shapes 0011 tested, 10 million iterations,
  at -O0 and at -O2 with nothing inlined       all complete
the compiler at -O0, compiling itself          on a 1 MB stack, with
                                               L0_RC_CHECK, output identical
the compiler's own IR                          898,092 -> 850,276 bytes
```

The IR is smaller because branches in tail position no longer store to a
slot and join. The compiler emits 336 `musttail` calls in itself, and 29
allocas remain, all for branches that are not in tail position. The compiler
IR assembles at `-O0` and `-O2` for x86-64, AArch64, RISC-V, and 32-bit ARM;
wasm refuses it at build time without the tail-call feature, as intended.
Both suites pass on macOS arm64, and on Linux aarch64 and x86-64 with
clang 18.

**What it costs.** Self-compilation went from 0.21 to 0.26 seconds,
including process start, best of three; not yet profiled. And the property
section 10.2 had, that a function's IR prototype is its L0 parameters and
nothing else, is gone.

**What was decided along the way.**

- *A builtin in tail position is not a tail call.* Builtins cannot recurse,
  and `head`, `tail`, and the others that borrow their argument release it
  after the call, which `musttail` would forbid.
- *No alloca moves to the entry block.* 0011 found that a loop within a
  function would allocate its join slots on every iteration. No emitted
  function has a back edge, so each alloca runs at most once per call, and
  10.4 now says a compiler that emits a loop must hoist them.
- *`main`'s body is `@l0_f_main.body`.* The runtime must keep calling
  `@l0_f_main`, because the seed defines that symbol and links against the
  same runtime. No L0 name can contain a dot, so the new symbol cannot
  collide with a program's function.
- *How deep recursion that is not a tail call may go is not specified,* and
  an implementation may run some of it in constant stack: LLVM already turns
  `(add 1 (count ...))` into a loop at `-O1`.

**Spec text corrected with it.** 10.3 said "a call in tail position stays
one", which was false for the emitted IR at every level, and that a streaming
program runs in constant memory, which held only for the heap. It now names
`L0_STACK_MB` and its 512 MB default.

---

## Memory is reclaimed by reference counting

**Programs now free memory.** The compiler emits reference counting, and the
runtime frees a block when its count reaches zero (section 10.3). Nothing a
program computes or writes changes. What changes is what it holds: a block is
freed no later than the end of the scope that bound the last reference to it.
This is the second of the two changes roadmap item 0010 planned; the first,
"Blocks describe their own layout" below, gave every block the header this
one needs.

**The blocker.** From roadmap item 0006, `0006/limits/02-no-reclamation.l0`: a
loop never holding more than about 1 KB live reached 9.8 GB after 10 million
iterations. Now:

```
   100000 iterations: rss 1.5 MB
  1000000 iterations: rss 1.5 MB
 10000000 iterations: rss 1.5 MB
```

A streaming program that builds a list for every line of its input, the
`tests/io/lines` numberer, holds 1.6 MB at 10 MB of input and 1.6 MB at 100
MB. The compiler compiling itself peaks at 26.3 MB, against 104.8 MB before
this item began on the same source and 179 MB after its first change.

**Why this scheme.** An L0 heap cannot contain a cycle, since there is no
mutation, evaluation is strict, and `let` cannot define a recursive value, so
counting reclaims everything with no collector. The emitter needs no analysis
of later uses: a use of a variable adds a reference, and the variable's own is
released when its scope ends. The one subtlety is tail position. `if` and
`match` join through a stack slot, so releasing at the end of a function would
put a release after every recursive call, and the loops LLVM now turns into
jumps would recurse instead and exhaust the stack. So in tail position every
binding in scope is released after the final call's arguments are evaluated
and before the call. That is also what frees a list as a loop walks it.

**What it costs.** Speed: every change to a count is a call into the runtime,
and the compiler compiling itself goes from about 0.04 to 0.15 seconds. Speed
alone does not justify a change here, but it is on record. And precision:
releasing at the end of a scope rather than at a value's last use means a
`main` that takes its input holds all of it while it runs. 0006's line filter,
written that way, still holds 2.7 GB at 100 MB of input, half of what it did.
Its `main` passes `input` to a call that is not in tail position, so `main`'s
parameter keeps the head of the list, and with it the whole list, alive.
Releasing at last use would fix it. That is recorded as its own roadmap item
rather than folded into this one, since streaming programs, which the l0-code
skill now recommends for large inputs, do not need it.

*Corrected later, the same day: that diagnosis was wrong.* A `main` that takes
its input and ignores it peaks at the same 2,504 MB at 100 MB of input as the
line filter does. The cost is the input list the runtime builds in full before
`main` starts, one 24-byte cons cell per input byte, and no rule for when to
release can reduce it; only the streaming form avoids it. A release-at-last-use
rule was built anyway, for variables used once outside any branch, and changed
nothing measurable: the line filter at 2.5 GB, the compiler at 26 MB and 0.15
s. It was reverted and roadmap item 0013 dropped. The paragraph above is left
as written, since it is the reasoning that opened 0013.

**How it was verified.** `L0_RC_CHECK` makes the runtime poison freed blocks
and never reuse them, so a use after free is a runtime error, and report any
counted block still live at a normal exit. The check was shown to fire, on a
program built by the previous compiler, which never releases. `tools/test.sh
--compiled` now runs every compiled program under it, the compiler included:
the bootstrap reached a byte-identical fixpoint on the first try, and the
compiler compiling itself under the check leaves nothing live and writes the
same bytes.

---

## Blocks describe their own layout, as the first step to reclaiming memory

**No change to what a program does.** Every block now has a header word in
front of it, holding a reference count, its size, and a mask of which of its
words are pointers (section 10.1); allocation goes through two new runtime
calls that take the mask (section 10.3); and a constructor may have at most
31 fields, a new compile error (section 4). Nothing is freed yet. This is the
first of the two changes roadmap item 0010 planned for reference counting,
and the reasoning for the whole design is recorded there.

**Why the mask comes from the compiler.** Freeing a block means releasing the
blocks it points to, so the runtime must know which words are pointers. For a
data block that follows from the constructor's field types. For a cons cell
it does not: whether the head is a pointer depends on the list's element
type, which only the checker knew, and at run time every value is one `i64`.
So the emitter now carries each expression's type as it emits it, computed
bottom-up exactly as the checker computes it, and passes the mask to
`l0_new_cons(head, tail, mask)` and `l0_new_data(tag, nfields, mask)`. That
refactor of the emitter is most of this change's risk, which is why it lands
before any counting: behavior is unchanged, so the whole differential suite
checks it against stage 0.

**Why 31 fields.** The mask is 32 bits of a one-word header and word 0 is the
tag. The widest constructor in the repository has 5 fields. One word keeps a
cons cell at 24 bytes rather than 32.

**Why the old calls stay.** The runtime interface is append-only, because the
seed declares its functions by name. `l0_cons` and `l0_data_new` remain, and
make blocks whose count is at its maximum, which means never freed. A program
an older seed compiled therefore keeps working unchanged once freeing exists.

**What it costs, measured.** One word per block: a cons cell grows from 16
bytes to 24, and the arena now rounds to 8 bytes rather than 16. The compiler
compiling itself, on the same 107 KB of source, goes from 104.8 MB resident
to 179 MB, which is more than the header alone. The rest is the emitter's own
new garbage, each value carrying its type and the call-type tables built per
call, and a 16% longer output, since every cons call now passes its mask.
Nothing is freed yet, so all of it accumulates. That is accepted as temporary:
the next change is what reclaims it, and roadmap item 0010's target, the
compiler below its old peak, is measured after that change and not this one.

---

## A test framework, and no language change for it

**No change to the language.** `lib/test.l0` and `l0 test` are a library and a
tool, built entirely on the I/O of the two entries below. This entry records
why they are shaped as they are, since the shape is what agents will copy.

**The blocker.** L0 had only a convention for tests, a `check` function
consing `y name` or `n name` onto `main`'s result. It never said what was
computed or expected; it put every assertion in one nest inside `main`, and
that nest is exactly where closing parentheses get miscounted, three times in
the session that built the two entries below; one runtime error ended the
whole run; and nothing gave an exit status or ran a subset.

**The shape, chosen with the user:**

- **Tests are found, not listed.** L0 has no function values, so a program
  cannot enumerate its own functions. The driver can, from the source: any
  `(def test_NAME () int ...)` is a test, and `l0 test` generates a `main`
  that runs the one named by `(arg 0)`. With nothing to register, the easy
  thing is many small tests, which is what keeps the parentheses short.
- **Each test is its own process.** The program is built once and run per
  test, so a runtime error fails one test, reported with its message. That
  also makes failure testable, which nothing in L0 can do otherwise, since
  runtime errors cannot be caught: `expect_NAME` names the error `test_NAME`
  must die with.
- **Assertions say what went wrong.** Each shows got and want, strings as L0
  literals that paste back into a test, with the first differing byte. Each
  writes as it runs and returns 1 on failure, so a test returns the sum, and
  `add`'s left-to-right order keeps the report in source order.
- **TAP**, because agents and CI already parse it, with a nonzero exit on any
  failure.
- **Golden files, filtering, and seeded random inputs** for large outputs,
  focused runs, and property tests. `--bless` lists every golden file it
  wrote, since blessing makes whatever the code does now correct.

**What it cannot serve.** Stage 0 cannot run I/O, so the oracle-checked suites
(`tests/lang`, the compiler's stage tests) stay on the old convention; the
framework is for `tests/io`, the standard library, program-writing workers,
and projects made by `l0 init`, which now ships `l0/test.l0` and a worked
`l0/examples_test.l0`. `tests/io/framework.sh` checks `l0 test`'s whole
report on a fixture against hand-written expectations, and runs the shipped
example tests, which must pass.

The repository's own tests of what stage 0 cannot run moved to it where they
could. `tests/unit/io_test.l0` has sixteen tests of `lib/io.l0` and the
builtins beneath it, taking over what the old `handles` program printed, and
`tests/unit/order_test.l0` checks evaluation order through a file instead of
standard output. `tools/test.sh --compiled` runs each through `l0 test` in a
scratch directory, and points it at the compiler it just built with the new
`L0_COMPILER` and `L0_RUNTIME` overrides, since `l0 test` otherwise uses the
seed's. What stays in `tests/io` is what a test function cannot check: the
two forms of `main`, exit status, standard input, arguments, and timing.

---

## Files, arguments, and names reserved for the standard library

**L0 can open files and read its command-line arguments.** Seven builtins,
over integer handles into a runtime table: `read_from`, `write_to`,
`open_read`, `open_write`, and `close` (section 6.3), and `arg_count` and `arg`
(section 6.4). Handles 0, 1, and 2 are the standard streams, so `read_byte` is
exactly `(read_from 0)`. Upper names beginning with `Io` and an uppercase
letter are now reserved for the prelude (section 7.1), which a program that
declared one will now fail to compile over.

**The blocker.** Roadmap item 0006 could not write a file copy: there were no
arguments, no files, and no way to fail but a crash. The checker confirmed
the missing pieces (`unknown function 'read_file'`, `unknown function
'write_file'`, `unknown function 'fail'`). `tests/io/filecopy` is now the
program 0006 said should have been possible. `filecopy.sh` checks a
byte-exact copy of 300 KB of random data, an existing destination emptied
first, and the exact message and status for a missing source, an unwritable
destination, an unreadable source, and a usage error.

**Why failure is a data type, and where the type lives.** "The route to memory
management and I/O" chose safe facilities partly because an operation that
can fail can return a data type with a failure case, and exhaustive `match`
then rejects a program that forgets it. So `lib/io.l0` declares `IoFile` and
`IoOpened`, with cases `IoOpened` and `IoFailed`, and wraps the builtins in
`open_in`, `open_out`, and friends. A program that matches on `(open_in path)`
and leaves out `IoFailed` does not type check.

The builtins themselves return negative codes rather than data types, because
a builtin's result type would have to be predeclared.

**Why reserve names.** Type and constructor names are one namespace across
the prelude and the program (section 7.1), for reasons that section records.
So any type the library declares breaks every program that already declared
the same name, and each later library type would do it again. Three answers
were weighed with the user: reserve a prefix for the library; group type and
constructor names per group, as functions are, which would touch about 44
resolution sites and override 7.1's stated reasons; or accept collisions.
Reserving was chosen. It is one checker rule, it can never break a program
again once made, and a reader can see which types are the library's. The
prefix is `Io` for what exists now; a later library area that needs types
gets a prefix of its own, which will itself be a breaking change for any
program that used it, once.

The rule is `Io` followed by an uppercase letter, so `IoFile` is reserved and
`Iota` and `Ion` are not. Only program declarations are checked. For that to
work outside `tools/l0`, `tools/l0c` and `tools/l0check` now put
`lib/prelude.l0` and `lib/io.l0` in the prelude group whenever `lib/io.l0` is
among their files, through a shared `tools/bundle.sh`; otherwise they
compile everything as the program, as before. `examples_check` checks the
examples the same way.

**What the runtime could and could not do portably.** It stays one text for
every host, so:

- files open with `open` and flags 0, since read-only is 0 everywhere, and are
  created with `creat`, since the values of `O_CREAT` and `O_TRUNC` differ
  between macOS and Linux
- `errno` is a macro over a function whose name differs between platforms,
  so the reason an open failed comes from `access()` instead. That is why the
  codes are few: no such file and permission denied can be told apart
  reliably, and everything else is -5
- a write failure can only be reported by `close`, since bytes may be held
  back until then; section 6.3 says so, and the l0-code skill tells programs
  to check it

Every handle is buffered. Standard output and error are flushed before any
read that has to wait, which keeps 6.2's prompt guarantee, and every handle
is flushed when the program ends, including by a runtime error.

**Verified on Linux too.** Both suites pass in an Ubuntu container, 56 and 62.
The permission case first failed there, because Docker's bind mount does not
enforce permission bits; on the container's own filesystem it passes, and
`filecopy.sh` now checks that case only where a mode-000 file really cannot
be read.

---

## Reading and writing as a program runs

**L0 has effects.** Two builtins, `read_byte` and `write_byte` (section 6.2),
and a second form of `main`, `(def main () int ...)`, which reads nothing up
front and returns the exit status (section 9). This is the first change made
under "The route to memory management and I/O" below, and the one that ends
L0's purity. Sections 1, 8, and 10.3 change with it.

**The blocker.** Roadmap item 0006 could not write a program that asks for a
name and then greets it. The nearest L0 program printed its question after its
answer, measured with the answer sent at t+0 and end of input at t+3:

```
  t+ 0.00s  stdin  b'Ada\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'What is your name? Hello, Ada!\n'
```

Now `tests/io/prompt` holds the program 0006 said should have been possible,
and `prompt.sh` sends the answer only once it has read the question back. A
version that reads before it asks fails it after its 5-second watchdog, which
was checked. The same change removes two of 0006's memory costs, the whole
input held before `main` runs and the whole output held until it returns. A
streaming copy of 1, 10, and 100 MB peaks at 1.1 MB each time, where `main`
returning its input peaks at 18, 173, and 1704 MB.

**Why bytes, and not lines or strings.** The builtins are the smallest pair
the rest can be written from, so the runtime interface grows by two functions
and not by a family. `read_line`, `write_str`, and `write_line` are ordinary L0
in a new `lib/io.l0`, which `tools/l0` links beside `lib/prelude.l0` in the
prelude group, so a program may define its own. `read_byte` returns -1 at end
of input rather than a data type with an end case, so it needs no predeclared
type: a predeclared constructor would break every program that already used
its name, since section 7.1 does not group constructors. That problem is still
waiting for 0009, whose file operations can fail.

**Why `lib/io.l0` is not in the prelude.** The stage-0 interpreter runs
`lib/prelude.l0` and the compiler, both for the compiler's stage tests and for
`tools/l0check`, and stage 0 is frozen, so it will never know the new
builtins. The compiler's own source and the prelude therefore must not use
them.

**Why a second form of `main`, and not only the builtins.** The existing form
reads all of standard input before `main` runs, so `read_byte` inside it can
only ever see end of file. A program that streams has to be one the host does
not read for. Its result became the exit status because nothing else is
written on its behalf, and a program that streams needs a way to fail other
than a crash. That is a first installment of 0009's "failure". The runtime
calls every `main` the same way, so one with no parameters still compiles to
`@l0_f_main(i64)` and ignores the argument (section 10.2), and
`@l0_main_ret_kind` gains a kind 3.

The old form keeps working exactly as before, and can use the builtins too:
`read_byte` returns -1 from the start, and bytes written come before the
result.

**What the ordering costs, which section 8 had already priced.** Evaluation
order was specified left to right from v1 "so that even failure is
deterministic", and its paragraph said an effect would find the order already
pinned down. It did. What is lost is the implementation's freedom to reorder
or drop an evaluation that could have an effect, and section 8 now says an
evaluation may be moved or dropped only if it can neither do I/O nor fail. The
compiler never used that freedom. LLVM cannot use it either, since the
builtins are calls into the runtime.

**Output buffering is specified by what it must not hide.** An implementation
may hold output back, but only until a `read_byte` has to wait, or the program
ends, including by a runtime error. That is exactly what makes a prompt
appear, and it lets the runtime buffer 64 KB in each direction. A runtime
error now delivers what was written before it and then the diagnostic, rather
than producing no output at all, since output that had already reached a
terminal could not be taken back.

**Section 10.3's case for the arena is corrected.** It said never freeing was
correct because a program "runs once and exits", and named a program that runs
unbounded as the change that would break it. A program that streams is that
change. The paragraph now says what is true: never freeing is safe, memory is
total allocation, and a streaming program that allocates per line grows
without bound while one that does not stays constant. 0010 is the fix.

**Tests without an oracle.** Stage 0 cannot run any of this, so the new
`tests/io/` suite runs only under `tools/test.sh --compiled`, and its
expectations are written by hand rather than blessed. Checker errors for the
new builtins and the new `main` are in `tests/compiler/check_errors`, which
runs the compiler's checker under stage 0 and so still has both.

---

## Checking a fragment still checks its main

**A check that used to pass now fails.** With `#nomain`, a program `main` that
is present must still have section 9's signature. Section 9.1 says so, and a
wrong `main` is now reported at its declaration, with a file and line, rather
than at no position.

**The blocker.** Roadmap item 0006 wrote this, to show that command-line
arguments cannot be reached:

```
(def main ((args (list (list int))) (input (list int))) (list int)
  (head args))
```

`tools/l0check` printed `ok` for it. Checking passes `#nomain`, and a present
`main` was not examined at all, although 9.1 said `#nomain` "relaxes nothing
else". Only `tools/l0 build` rejected it, with no location:

```
error: main must take one parameter of type (list int)
```

The worker nearly recorded a blocked program as passing, because the one rule
it had been given was to trust `l0check`. A checker that says `ok` about a
program that cannot run is worse than one that says nothing.

**`tools/l0check` now uses the compiler's checker.** It used to run stage 0's,
which is frozen, so it could not have been fixed there. The compiler's checker
runs under the stage-0 interpreter, which executes the current
`compiler/*.l0` and so is never stale, and it takes about a tenth of a second
on a 30 KB file. This also had to happen before the next language item: once
L0 gains builtins stage 0 does not know, stage 0's checker would reject every
program that uses them. Stage 0's checker remains in use as the oracle in
`tools/test.sh`, which is its only job. Diagnostics now carry the compiler's
wording, which differs slightly from stage 0's.

When the compiler's own source starts using a feature stage 0 cannot run,
`l0check` will need a native compiler built from the current source instead.
It falls back to `build/l0c-native` already, but that one is only as current
as the last `tools/test.sh --compiled`.

**One more stale-compiler trap, found verifying this.** In a checkout,
`tools/l0` rebuilt `lib/l0c` from the seed only when it was missing, so after
a seed refresh `l0 check` and `l0 build` went on using the previous compiler,
and reported the old unlocated message. It now rebuilds when the seed or
`runtime/l0rt.ll` is newer than what it built. An installed prefix has no
seed beside it and is unaffected.

---

## The route to memory management and I/O

**No semantic change yet. L0 is exactly the language it was before this
entry.** What this records is a decision about what L0 becomes, made before
any of it is built, because it ends a property the spec has had since v1.

**The decision.** L0 gains memory management and I/O as safe facilities
implemented in the runtime, and I/O becomes effects in expression position,
ordered by section 8's existing left-to-right rule. L0 code does not get raw
memory. This ends L0's purity, deliberately. Section 8's guarantee that a
program which type checks cannot read uninitialized memory stays whole.

**The evidence.** Roadmap item 0002 tried to write the runtime in L0 and
found ten limits, every one of them a systems primitive: loads and stores at
an address, static storage, calls to C, symbol names, C types. Item 0006 then
wrote four ordinary programs, a line filter, a word counter, a prompt, and a
file copy. None of them needed any of those primitives. What they needed was
reclaimed memory, incremental standard input and output, arguments, files,
and a way to fail. The prompt and the file copy cannot be written at all
today, and the two that can are costly, measured:

- the line filter uses 53 bytes of memory per input byte, 16 GB for one pass
  over 300 MB
- the word counter, whose table never holds more than 14 entries, uses 208
  bytes per input byte
- a loop that never holds more than about 1 KB live reaches 9.8 GB after 10
  million iterations

**Why safe facilities rather than primitives.** L0 is written by agents, so
what counts is whether the checker catches their mistakes. An operation that
can fail can return a data type with a failure case, and exhaustive one-level
`match` then rejects a program that forgets the error path. Raw memory gives
the checker nothing: every value is an `i64` at run time, so a wrong pointer,
length, or errno passes. And freeing by hand cannot be made safe in L0 at all,
because lists share their tails invisibly.

**Reclamation will be reference counting.** It is complete for L0 without a
cycle collector: there is no mutation, evaluation is strict, and `let` cannot
define a recursive value (section 5.3), so an L0 heap can never contain a
cycle. It is also invisible to programs, so the whole differential suite
keeps judging it against stage 0.

**What this overrules.** "Output before input is an accepted blocker" below
preferred keeping `main` pure and re-running it on a longer transcript each
turn. That fixes prompting and nothing else: for the word counter it would
mean 2.8 million re-runs on 100 MB of input. Its blocker and measurement
stand; its preferred shape is rejected on this evidence.

**What was deferred, not rejected.** The systems primitives return to the
table if a program needs them, or if writing the runtime in L0 becomes a goal
in its own right. `roadmap/0002/` holds their list and first drafts.

**The order.** Checking enforces `main`'s signature first, a small fix 0006
found. Then streaming standard input and output, then arguments, files, and
failure, then reference counting. Streaming comes before reclamation because
it changes what can be written, not only what it costs, and 0006 measured
that neither bounds memory without the other.

---

## The runtime is LLVM IR, and stack exhaustion is checked rather than caught

**No change to what an L0 program means.** Every program produces the same
output, the same errors, and the same exit status as before. What changed is
what a compiled program is made of. Section 10.3 now says the runtime is LLVM
IR that calls libc, and adds one function to it, `@l0_stack_check`, which
every compiled function calls on entry.

**The blocker.** Every compiled program linked `runtime/l0core.c` and
`runtime/l0rt.c`, and "A new goal" below makes no C source in a compiled
program the first milestone. Roadmap item 0001 set out what the C did and
what each part needed from the operating system. Lists, data blocks, `div`,
`mod`, and error reporting need nothing but an allocator and `write`.
Allocation needs `malloc`, input and output need `read` and `write`, and the
entry point runs the program on a 512 MB thread so that deep recursion works.

**The replacement** is `runtime/l0rt.ll`, hand-written IR that calls 14 libc
functions and nothing else. It exports the same names the C did, so the
checked-in seed, which declares them, links against it unchanged. It carries
no target triple, and it is the same text on every host because it avoids
everything whose shape differs between operating systems:

- file descriptors rather than `FILE*`, whose symbol names differ
- no varargs, so no `printf`; decimal output is written out by hand
- `pthread_attr_t` as an opaque buffer larger than any platform's
- no signal handling at all

A prototype was measured before this change was made. On macOS arm64, and on
Linux aarch64 under Docker (Ubuntu 24.04, glibc, clang 18), with identical
results on both, it passed all 30 compiled tests against the interpreter's
expectations, and the compiler linked against it compiled itself
byte-identically.

**Why the stack is checked rather than caught.** The C runtime reported
exhaustion from a SIGSEGV/SIGBUS handler running on an alternate stack.
`struct sigaction`, the value of `SA_ONSTACK`, and the number of `SIGBUS` all
differ between macOS and Linux, and target-independent IR cannot express any of
them. So the thread records a limit when it starts, 256 KB above the bottom of
its stack, and each function compares its frame address against it. The cost
is one call per function entry. Measured against the C handler, exhaustion is
reported at exactly the same depth for every `L0_STACK_MB` tried, from 1 to
512.

The big stack stays, and is still sized by `L0_STACK_MB`. The compiler does
not need it: at `-O2`, LLVM turns its recursion into loops, and it compiles
itself on 1 MB. User programs do. Recursion that LLVM cannot rewrite, such as
rebuilding a list through `cons`, costs 32 bytes a frame on arm64, so the
default 8 MB stack fails on a 1 MB input that 512 MB handles. macOS could set
that size at link time, but Linux has no equivalent, so it is still a thread.

**A trap in the transition, and why this landed with a fresh seed.** The
compiler now emits the checks, but the seed predates them, so a compiler built
from it produces programs with no stack checks. Linked against the new
runtime, those programs crash with a bus error on deep recursion rather than
reporting it. Nothing in the test suite would have caught this, because
`--compiled` bootstraps from source first. It showed up only through
`l0 build`, which uses the installed compiler. So the seed was refreshed in the
same change, and there is no commit at which the installed toolchain loses the
error.

`tests/lang/err_stack` is new. Stack exhaustion had no test before.

**What stays C.** Only stage 0. `runtime/l0core.c` is now compiled for the
interpreter alone, and `tools/install.sh` compiles no C at all. `l0rt.c` is
linked by nothing; roadmap item 0004 deletes it and moves `l0core.c` under
`stage0/`.

---

## A new goal, and the agent that uses L0 is the one that changes it

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what L0 is for, and how it changes.

**The goal.** The README opened with a goal that has been met: "L0 does not
aim to be fast, general, or pleasant for humans. It aims to be expressive
enough to express its own compiler." "Purity is a property, not a premise"
below stopped the spec from treating self-compilation as the only goal, but
left the direction to whatever applications happened to request. The goal is
now stated in its own right, in three parts:

- **Compiled.** L0 compiles to native code through LLVM and is never
  interpreted at run time. That is the only sense in which it aims to be fast.
  Tail calls, inlining, and register allocation are left to LLVM, so L0 does
  not implement optimizations itself, and speed alone does not justify a change.
  Section 8 still leaves tail-call elimination unspecified; this is a statement
  of where the work lives, not a new guarantee.
- **General purpose.** L0 should express ordinary programs, not only its own
  compiler. Memory management and I/O come first, and the direction is for
  compiled programs to stop needing the C runtime in `runtime/`. That makes the
  cost notes in section 10.3 and in "Output before input" below live questions
  rather than hypothetical ones.

  "Without the C runtime" means no C source in a compiled program, not no
  libc. libc stays as the interface to the operating system, because on macOS
  it is the only supported one: Apple does not keep the raw system call ABI
  stable, which is why Go calls libSystem there rather than the kernel. A
  program that makes raw system calls would be Linux-only, and nothing in the
  goal is worth that.
- **Written for agents, not humans.** This is the one part of the old "does not
  aim" list that survives. L0 is read and written by an agent, so whether code
  comes out correct, and whether the checker catches it when it does not,
  outweighs brevity and familiarity.

Self-compilation stays the one property no change may cost.

**The process.** The request loop is retired: the `l0-limits` skill in
scaffolded projects, `l0 request` and `l0 submit`, the `requests/` inbox, and
triage here by the `l0-evolve` skill. It was too tedious to operate, and the
agents in those projects were too quick to work around a limitation instead of
reporting it.

The loop's own rules made that the expected outcome. The toolchain was
read-only, a workaround had to exist before a request could, and a cost that
was constant per use site was to be worked around "however tedious". Two
results of that are already on record. The compiler carries nine
near-identical result types for want of generics, which never qualified. And
the hell0 project shipped a greeting program that "does something adjacent to
what was asked, and its test suite passes" (see the entry below). A workaround
that ships absorbs exactly the pressure a language change needed.

Now the agent that writes L0 in this repository also changes it, and when L0
cannot express something the answer is to change L0. A change is still earned
by code — L0 in this repository that it makes possible, or makes harder to get
wrong — and the spec-first order, the two-step rule, and the frozen stage 0 are
unchanged. Those rules moved from the deleted `l0-evolve` skill into
`l0-bootstrap`, so that one skill covers every change that has to survive the
bootstrap.

`l0 init` still scaffolds a project with the spec, the examples, the prelude,
and the `l0-code` skill. The `AGENTS.md` it copies now tells an agent to name a
limitation plainly rather than ship a narrowed version of the task, since
nothing any longer carries a report back here.

**Earlier entries** cite `requests/`, `l0-limits`, and `l0-evolve`. They are
left as written; the files are in git history. Where a decision rested on the
loop's tests for change — constant per use site, three unrelated places, a
host-protocol question rather than a language one — it is to be re-argued
rather than inherited, as "Purity is a property, not a premise" already said of
purity.

**What did not change, deliberately.** The restrictions formerly under "What
makes a good feature" still stand: one-level `match` with no wildcard, no type
inference, `list` as the only parametric type, and no function values. Their
reason is restated for the new goal rather than dropped. They keep the checker
simple and every error local, which serves an agent writing L0 as much as it
served the bootstrap. Breaking one is allowed, and should buy something
substantial.

---

## Output before input is an accepted blocker

**No semantic change. L0 is exactly the language it was before this entry.**
Section 9 still has the host read standard input to end of file, then evaluate
`(main input)`, then write the result, and nothing in the grammar, the type
rules, the runtime, or the emitted IR has moved.

What this entry records is that the blocker behind a future change to that
ordering has been demonstrated, checked here, and accepted. It is written now
because the demonstration lives in a project that may change, and because the
same blocker arrived twice from the hell0 project, as requests `hell0-0001`
and `hell0-0003`, and was argued from scratch both times. The requests
themselves were retired with the request loop (see the entry above); what
mattered in them is quoted here.

**The blocker.** From `hell0-0003`, which states the task and the obstacle:

> The task: ask the user for their name, then greet the name they gave. One
> turn — write, then read what the writing caused.
>
> No L0 program can do this, and the obstacle is not syntax, so there is no
> code that fails to compile. What fails is the order.

The nearest expressible program returns the question and the answer together,
and so "prints `What is your name? Hell0, Ada!` — a question printed after its
own answer was consumed. The bytes are in the right order on screen and in the
wrong order in time."

**The measurement**, which is the part that would otherwise be unrecoverable.
`test/ordering/measure.sh` in that project supplies the answer immediately and
delays only end of file, so the two hypotheses predict outputs three seconds
apart. Reproduced here:

```
answer is readable at t+0; end of file comes at t+3s

  t+2.98s  got: Ada
  t+2.98s  |end

first output byte at t+2.98s.
```

> The answer was readable at t+0. No output byte appeared until t+2.98, when
> EOF arrived. [...] The program cannot emit a prompt while the user is still
> able to respond to it, on any input, because evaluation has not begun.

The script exits 0 while the limitation holds and nonzero if output ever
appears early, so it is also the check that would tell us this had been
fixed. `nm` on `lib/libl0rt.a` agrees from the implementation side:
`l0_read_stdin_list` and `l0_write_result` are the only symbols that touch the
byte channel, so there is one read and one write and no way to interleave them.

**What the workaround costs.** There is no workaround that performs the task:

> **The program cannot be written.** Not awkward — impossible. The requirement
> is that the program's output influence its own input. Section 9 orders all
> reading before all evaluation, so the two cannot both hold, and no amount of
> structure on the byte channel changes it: a format says what bytes mean, not
> whose turn it is.
>
> The cost is not line count. It is that the shipped program does something
> adjacent to what was asked, and its test suite passes, because the tests were
> written from the same contract.

What shipped is a program that greets a name on stdin and never asks for one —
"honest and it is not the task. An observer watching it run is never asked
anything." A bash wrapper that did the asking was tried first and rejected,
for a reason worth keeping: the turn lived in the shell, so the L0 half could
not decide whether to ask, or ask a second question whose wording depended on
the first answer.

> This generalises past greeting: a confirmation prompt, a menu, a retry on
> invalid input, and progress during a long run are all the same limitation.

**Why this is not the ordinary host-protocol case.** It was the one carve-out
in the `l0-limits` skill, and that carve-out existed because of this same
project's earlier skill note: structure says what bytes mean, it cannot say
whose turn it is. The precedent for reaching for a format instead of a feature
is strong — see "Input bundle" and "Compiler output protocol" below, three
problems in a row that looked like they needed a primitive and needed none —
but all of that evidence comes from the compiler, which is a batch program that
never wanted a turn. It is evidence about content and silent about ordering.

**What is accepted, and what is not.** The blocker, and the general shape of
the fix: `main` stays a pure function from bytes to bytes and is re-run on a
longer prefix of the transcript each turn, recomputing rather than resuming, so
nothing captures a continuation and determinism and replay are preserved.

Not accepted, twice now, is putting the turn directive in the type system — a
predeclared `Turn`, or the `Step`/`Done`/`More` of `hell0-0003`. Section 7.1
does not group type and constructor names, and "Why types and constructors are
not grouped" below records that as structural rather than an oversight, so a
predeclared constructor breaks every program that already used the name, with
no shadowing escape. The directive belongs on the byte channel, where the
compiler already puts `O` and `E`, which costs no name, no second entry point,
and no checker case.

**What it will cost when it is made**, so that the price is on record:

- **Sections 1 and 9.** The purity boundary moves. Individual `main` calls stay
  pure and the language still has no I/O primitive, so section 8 is untouched
  and evaluation order stays unobservable. This is why a host loop is much
  cheaper than an effect in expression position.
- **Section 10.3, which asks to be costed directly.** `hell0-0003` is the first
  request to do so, and its answer is accepted: re-entry is bounded by the turns
  the program asks for, the process still runs once and exits, so the bump arena
  stays correct, and a program demanding unboundedly many turns exhausts the
  heap — already a runtime error under section 8, already reachable through
  unbounded recursion. What is given up is the guarantee that total allocation
  is bounded by a single evaluation. A fresh process per turn avoids even that,
  which is why the out-of-process loop is the cheaper first step.

Streaming `main`'s result as it is produced was considered and is a different
change. It would fix progress reporting and not prompting, since stdin is still
consumed before `main` is called, and doing it properly needs non-strict
evaluation, which section 8's strictness rules out as load-bearing.

*Qualified later, by "A new goal": I/O is now a goal in its own right rather
than something an application has to prove it needs. The blocker and the
measurement above stand. The preference for keeping `main` pure and moving
the turn into a host loop was argued under the old goal, when the aim was to
change as little as possible, and is one candidate to re-argue rather than the
settled shape.*

---

## Purity is a property, not a premise; self-compilation is not the only goal

**No semantic change. L0 is exactly the language it was before this entry.**
Nothing in the grammar, the type rules, the runtime, or the emitted IR moved,
and no test changed. What changed is what the spec claims about its own
permanence, which had started to govern decisions it was never meant to govern.

**The blocker.** Two sentences in the spec's opening — "L0's single goal is to
be able to compile itself" and "Everything in this document exists because it
serves that goal" — were written before self-hosting was reached. They are a
true account of how v1 came to be and a false account of what governs L0 now.
The `l0-evolve` skill already says the opposite: "Self compilation supplied
that pressure until it was reached; applications written in L0 supply it now."
A spec and a skill that disagree about what justifies a change is not a
cosmetic problem, because the spec wins, and the spec's version rejects on
sight any request arising from an application rather than from the compiler.

That is not hypothetical. `requests/hell0-0001-interactive-input.md` asks for
interactive prompting, which self-compilation will never need: the compiler is
a batch program. Under the old opening the request is refused without reading
the evidence. Under the new one it is judged on whether the blocker is real.
The ambiguity was deciding requests by itself, which is the one thing an
ambiguity must not be allowed to do.

**Smallness.** No rule anywhere required L0 to stay small, and none does now.
What exists is a bar for change — it grows when real code cannot be written
without the addition — which is a justification requirement, not a size cap.
The opening now says smallness is a description rather than a vow, so that the
bar is argued about on its own terms.

**Purity.** Three rules leaned on purity, two of them silently, and the fix is
to name the dependency at each site rather than to weaken any of them:

- Section 8 derived the unobservability of evaluation order from purity. The
  left-to-right rule itself never depended on purity and is unchanged; what
  purity buys is an implementation's freedom to reorder pure arguments. That
  is now stated as the thing a change would cost.
- Section 10.3 said the bump arena is correct "because an L0 program is a
  single pure evaluation that runs once and exits". Purity was doing no work
  in that sentence. The arena is correct because the run is *bounded*, and an
  impure L0 that still ran once and exited would not disturb it. Section 10.3
  now says so, and names re-entry and unbounded running as the changes that
  would put a collector back on the table. This is a real finding rather than
  a rewording: it means a resumable entry point is an allocator question,
  which nothing in the spec previously said.
- Section 1 asserted purity flatly. It now adds that the impurity lives in the
  host by v1's choice of boundary, and points at the two sections above.

The claim that purity was merely the cheapest route to bootstrapping does not
survive the record, and is not the reason for this entry. Purity was a
deliberate placement — see "An entry point and a host contract" below: "this
adds no I/O to L0 itself: `main` is still a pure function, and the impurity
lives entirely in the host." It remains load-bearing. The point of naming what
rests on it is that a future proposal can price the change instead of
discovering the dependencies one broken derivation at a time.

**What did not change, deliberately.** The language must still be able to
compile itself. That is now stated as the one property no change may cost,
which is a stronger and narrower claim than "everything serves that goal": it
forbids a change that breaks self-hosting, and permits one that merely fails to
advance it. Every restriction in "What makes a good feature" also still stands;
this entry loosens the stated *purpose* of the language, not the bar any
individual change has to clear.

A program may now define a function the prelude already defines. The program's
definition wins throughout the program; the prelude goes on calling its own.
Spec section 7.1 states the rule, 9.1 states how a compiler is told where the
boundary is, and 10.2 gives the prelude its own symbol prefix.

**The blocker.** Before this, the prelude occupied the same flat namespace as
the program, so a project that had written its own `length` could not compile
at all:

```
clash.l0:1:1: error: function length is already defined
```

That makes every addition to `lib/prelude.l0` a breaking change for programs
that already exist, and the hazard grows with the prelude: the more it holds,
the likelier any given project has already used one of the names. This is the
"cost grows with the program" case in the `l0-limits` skill, and it is the one
cost of prelude growth that the emitted-linkage change immediately before this
did not touch. Compiled size was the other, and is now nothing.

The workaround was `l0 build --no-prelude`, which trades one name for the
whole library, and which the shipped `AGENTS.md` did not even mention.

**Why two groups and not a module system.** A general module system was
considered and rejected. Imports would mean path resolution inside a compiler
that is by definition a pure function from bytes to bytes, so the work lands in
the driver either way; what it would buy is separate compilation, which this
project does not want, because whole-program checking is exactly what lets the
checker do without inference. Measured by the `l0-limits` test, needing to name
every file on one command line is a cost that is constant per use site. Name
isolation was the only part that was not.

So the addition is deliberately not general: there are exactly two groups, not
n, nothing in a source file can say what it needs or exports, and the grouping
comes from the input protocol rather than from L0 syntax.

*Qualified later, by "Purity is a property, not a premise": "by definition a
pure function from bytes to bytes" describes v1, not a fixed truth. The
argument above is left as it was made, since it is the reasoning that was
actually used. If purity is ever revisited, this rejection is one of the
things that has to be re-argued rather than inherited.*

**Why the program's definition does not simply replace the prelude's.** The
cheaper rule — one namespace, last definition wins — was rejected because it
is monkey-patching. A program defining its own `list_eq` would silently change
what the prelude's `any_eq` and `index_of` do, and nothing would report it.
Two scopes cost a symbol prefix and catch that at the point of definition
instead, which is the trade this project has taken every other time it came
up.

**The compiler itself is still compiled as one group.** `tools/l0` marks the
prelude for a user's program; `tools/l0c`, which builds this repository and
runs its tests, does not, because when the compiler is built `lib/prelude.l0`
genuinely is part of the program rather than a library beneath it. So
`bootstrap/stage2.ll` carries `@l0_f_length` and not `@l0_p_length`, and the
grouping is exercised by `tests/compiler/prelude_scope` and
`tests/compiler/bundle_prelude` rather than by the bootstrap. This also kept
the two steps apart: the compiler learned to read `#prelude` and the seed was
refreshed before any driver started writing it, so no fresh clone ever sees a
header its only compiler cannot parse.

**Why types and constructors are not grouped.** A `match` arm names a
constructor without naming its type, so constructor resolution has to be
global for one-level patterns to resolve at all, and `ty_eq` compares types by
name, so two same-named types could not be told apart. Grouping function names
needs neither. The restriction is recorded in 7.1 so that a later attempt to
group them starts from the reason rather than from the omission.

---

## Emitted linkage — resolved

Every function except `main` is now emitted as `define internal`, so the
prelude no longer costs anything in a program that does not use it.

No language change. The spec does not describe linkage, and it still does not:
this is a fact about the emitter, recorded because the reasoning behind it is
what makes the next question answerable.

The old emitter gave every function external linkage. Nothing can remove an
externally visible symbol, so a hello-world compiled with the prelude carried
all 30 prelude functions into its object file at 10704 bytes, of which it
called none. With internal linkage on everything but `main`, LLVM's `-O2`
deletes the unreachable ones and the same object is 1168 bytes.

`main` stays external because [../runtime/l0rt.c](../runtime/l0rt.c) calls
`l0_f_main` by name, and `@l0_main_ret_kind` stays a plain global for the same
reason. Those two symbols are the entire interface a compiled program exposes;
a program is otherwise a closed module, which is what makes internal linkage
correct rather than merely convenient.

This was prompted by the observation that `lib/prelude.l0` will keep growing
and that every program pays for all of it. Half of that was true and is now
false. What remains true is that the prelude occupies the same flat namespace
as the program, so a project that defines its own `length` cannot compile:

```
clash.l0:1:1: error: function length is already defined
```

That is the cost that actually grows with the prelude, and it is a language
question rather than an emitter one. Recorded here as open, deliberately
separate from this change. Compile time is not part of the picture: the whole
prelude adds about 2 ms to a hello-world.

The seed was refreshed in the same change, since the emitter's output shape
changed. The fixpoint held first: a seed built before this change compiles the
new compiler to `stage1.ll` with the old linkage, and that compiler then
reaches `stage2.ll == stage3.ll` with the new.

---

## Self-hosting reached

`compiler/*.l0` compiles itself to a byte-identical fixpoint, and
`bootstrap/stage2.ll` is checked in as the bootstrap seed. Verified by
removing `stage0/` entirely and rebuilding the compiler from the seed alone.

No language change was needed to get here. L0 v1 as specified was sufficient
to express its own compiler, which was the entire point of the design.

Two things are worth recording because they were predicted and held:

**The monomorphism pressure never became a blocker.** The compiler carries
nine near-identical "value or error" result types that a parametric data type
would collapse into one. That was annoying and never worse than annoying, so
parametric data types remain unjustified. The blocker that would justify them
has still not appeared.

**Nothing needed I/O.** The compiler is a pure `(list int) -> (list int)`
function, and everything that looked like it wanted a primitive turned out to
be a protocol on the single channel instead.

---

## Input bundle — resolved

Diagnostics now report `file:line:column` rather than a line number in the
concatenated stream, and again no language change was needed.

Input may optionally begin with a table of byte offsets and paths:

```
#l0bundle
0 util.l0
41 main.l0
#source
<the concatenated file contents>
```

The compiler maps a diagnostic's byte offset back to the file containing it
and measures line and column from that file's start.
[../tools/l0c](../tools/l0c) builds the bundle. Input that does not begin with
`#l0bundle` is treated as a single unnamed source, so piping a bare file still
works and the bootstrap is unaffected.

This was recorded as an open question and became worth fixing the moment the
compiler was pointed at a real multi-file project: an error on line 2 of the
second file was reported as line 3, which points at nothing and sends the
reader to the wrong place entirely.

That makes three problems in a row that looked like they wanted an I/O
primitive and were solved instead by putting a little structure on the single
byte channel. The pattern is worth trying before reaching for a language
feature.

---

## Compiler output protocol — resolved

The question of how a compiled program distinguishes "here is my output" from
"I failed, and here is why" is settled, and needed no language change.

`main` returns a **tagged stream**: `O` and a newline followed by LLVM IR, or
`E` and a newline followed by diagnostics, one per line.
[tools/l0c](../tools/l0c) strips the tag, routes the remainder to stdout or
stderr, and sets the exit status, so callers see an ordinary unix compiler.

A printable tag was chosen over a leading zero byte so that raw compiler
output stays readable under `head` while debugging.

This confirms the reasoning recorded when the question was opened: a pure
`bytes -> bytes` function plus a slightly richer host protocol goes much
further than it appears, and the things that look like they need I/O
primitives usually do not.

---

## v1 — initial spec, superseding the seed

[L0.md](L0.md) replaces [../seeds/spec.md](../seeds/spec.md) as the single source
of truth. The seed is kept unchanged for history.

### Added

**String literals.** `"add i64 "` denotes a `(list int)` of byte values.
*Reason:* the compiler's entire output is text. Without literals, every emitted
fragment would be a hand-written `cons` chain, which is unreadable and
unmaintainable at the scale of a code generator.

**Parametric lists, `(list T)`.** The seed had a single `list` type meaning
"sequence of int". *Reason:* a compiler needs a list of tokens and a list of
declarations, not just a list of integers. This is the one generic type
constructor in L0; user data types are monomorphic, which avoids needing
unification or type inference anywhere in the checker.

**`data` declarations and `match`.** Tagged unions of fixed-arity constructors,
with one-level-deep exhaustive pattern matching. *Reason:* an abstract syntax
tree is a sum type. Without one, the AST would have to be encoded into a flat
`(list int)` with a hand-rolled allocator, making every access O(n).

Patterns are deliberately restricted to one level with no wildcard arm, so
exhaustiveness checking is a matter of counting constructors and `match` codegen
is a jump table. Nested patterns would require a pattern-match compilation
algorithm in the self-hosted compiler, which is a large amount of work for
convenience alone.

**An entry point and a host contract.** A program declares `main`, the host
supplies stdin as a byte list and writes the result to stdout. *Reason:* the
seed spec described a language in which nothing could be run or tested. Note
that this adds no I/O to L0 itself: `main` is still a pure function, and the
impurity lives entirely in the host.

**A compilation target (section 10).** Value representation, generated symbol
names, and the runtime interface. *Reason:* the L0 compiler must emit exactly
this, so it is part of the language's contract rather than an implementation
detail. Pinning it down also allows the "every value is an `i64`" simplification
to be relied upon rather than rediscovered.

### Changed

**`int` is 64-bit, not arbitrary precision.** *Reason:* the seed promised
arbitrary precision, which means shipping a bignum library in the runtime before
a single L0 program can run. GMP is not installed, and a self-hosting compiler
never needs a value above 2^63. Keeping the spec honest matters more than
keeping it ambitious, because the spec is an agent's only source of truth and an
aspirational claim here would become a silent correctness bug.

**`nil` is an expression form, not a builtin.** It is now written `(nil int)`
with an explicit element type. *Reason:* with parametric lists, bare `(nil)` has
no determinable type. The alternative was bidirectional type checking to
propagate an expected type inward, which is real machinery and interacts badly
with recursion and `if` branches. An explicit type argument keeps the checker
completely inference-free.

**Names are split into lower and upper by first character.** Functions,
parameters, and bindings are `[a-z_]...`; types and constructors are `[A-Z]...`.
*Reason:* it lets a reader distinguish a constructor from a variable with no
context and no symbol table, which keeps both the parser and the eventual
self-hosted checker simple.

**`int`, `bool`, and `list` joined the reserved words**, alongside the seed's
`def`, `if`, `let`, `true`, `false`, plus the new `data`, `match`, and `nil`.

### Resolved ambiguities

The seed spec did not settle these. Each was decided to keep the language
deterministic and the checker simple; any of them can be revisited.

**Argument evaluation order** is left to right. *Why it matters:* L0 is pure, so
order is unobservable except for which runtime error fires first. Specifying it
makes failure deterministic, which in turn makes error tests reproducible.
*(Still the rule. See "Purity is a property, not a premise": the ordering does
not depend on purity, so a change to purity would cost the unobservability and
leave the left-to-right rule standing.)*

**`mod` takes the sign of the dividend.** The seed said division truncates
toward zero but did not say what `mod` does with negatives. Truncated division
implies the remainder follows the dividend, so `(mod -7 2)` is `-1`. This is what
LLVM's `srem` and C both do, so it is free to implement.

**Overflow wraps** rather than trapping, including the three cases that would
otherwise be undefined: `(div INT_MIN -1)` is `INT_MIN`, `(mod INT_MIN -1)` is
`0`, and `(neg INT_MIN)` is `INT_MIN`. *Why:* wrapping maps directly onto LLVM
arithmetic at zero cost. The three special cases are called out because LLVM's
`sdiv` and `srem` treat them as undefined behavior, so the runtime must handle
them explicitly to keep the language total.

**`let` shadowing is allowed.** An inner binding shadows a parameter or an
enclosing binding of the same name. *Why:* forbidding it forces gratuitously
unique names in deeply nested code, and accumulator-passing style produces a lot
of nesting.

**Locals and functions occupy separate namespaces** (section 7). A lower name in
call position is always a builtin or a `def`; a lower name anywhere else is
always a local. *Why:* L0 has no first-class functions, so a local can never be
called and a function name can never be a value. Making the rule syntactic
removes an entire class of resolution ambiguity, and it means a parameter named
`length` does not shadow a function named `length`.

**Shadowing a builtin is legal but the builtin always wins** in call position,
which makes a `def` named `add` uncallable. Rejecting it outright would be
defensible; allowing it keeps the resolution rule uniform, and it is a lint
concern rather than a correctness one.

**`eq` remains int-only.** Comparing lists or data values is a function written
in L0. *Why:* structural equality on arbitrary types is a polymorphic builtin
whose implementation needs runtime type information, which the "every value is
an `i64`" representation deliberately discards.

**Duplicate declarations are errors**, enumerated in section 4: duplicate
functions, duplicate types, duplicate constructors even across different types,
and duplicate parameter names. Constructors share one global namespace because
`match` arms name a constructor without naming its type, so the constructor has
to determine the type on its own.

**A `data` declaration needs at least one constructor.** An empty one would
declare an uninhabited type, which is useless here and would make `match`
exhaustiveness vacuous.

**`match` has no wildcard and no default arm**, and every constructor must appear
exactly once. *Why:* adding a constructor to a `data` type then becomes a compile
error at every site that must handle it, which is the property that makes
evolving the compiler's own AST safe.

**Recursive and mutually recursive data types are allowed**, since trees are the
point.

**String literal details.** The escape set is exactly `\n \t \r \\ \" \xHH`; any
other escape is an error. A raw newline inside a string literal is an error, so
that an unterminated string is caught on its own line instead of swallowing the
rest of the file. Literals produce unsigned bytes, never negative elements.

**Integer literal details.** A literal must fit in 64 bits, and a `-` is part of
a literal only when immediately followed by a digit. `- 3` is an error rather
than a subtraction, because `-` is not a name in L0.

**Runtime errors exit with status 70** and write one line to stderr, producing no
stdout. 70 is `EX_SOFTWARE` from `sysexits.h`, chosen so it cannot be confused
with a type error (status 1) or with a signal.

**Stack and heap exhaustion are reported as runtime errors** in the same form.
They are the only two failures a well-typed program can suffer that are not in
the list of four, and since L0 has no loops and no tail-call guarantee, deep
recursion is a realistic outcome rather than a pathological one.

**Output bytes are reduced modulo 256.** `main` returns a `(list int)` whose
elements are full 64-bit integers, so out-of-range elements need a defined
behavior. Truncating is quieter than erroring and matches how the bytes were
produced on the way in.

**Multiple source files are concatenated.** Declaration order is already
irrelevant, so file splitting is an editing convenience with no semantics. This
avoids designing a module system, which the bootstrap goal does not require.
