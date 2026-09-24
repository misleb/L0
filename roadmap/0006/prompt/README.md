# prompt: ask for a name, then greet it

**Status: blocked. There is no L0 program here, because none can be
written.** Printing the question after the answer has been read would be a
different program. The task is that the question appears *before* the user
answers.

The obstacle is not syntax, so the evidence is a timing. The nearest program
L0 can express is [limits/04](../limits/04-no-output-before-eof.l0), which
returns the question and the greeting together. `measure.sh` times it, next
to a four-line sh program that performs the task, using
`../common/timeline.py`, which writes stdin on a schedule and timestamps each
output chunk as it arrives.

| File | What it is |
| --- | --- |
| `answer.txt` | the test input, `Ada` |
| `measure.sh` | the timings below |

## A: `(sleep 3; echo Ada) | prog`

```
L0 (limits/04):
  t+ 3.00s  stdin  b'Ada\n'
  t+ 3.00s  eof    b''
  t+ 3.00s  stdout b'What is your name? Hello, Ada!\n'
  t+ 3.00s  exit   b'0'
first output byte at t+3.00s.

sh reference:
  t+ 0.31s  stdout b'What is your name? '
  t+ 3.01s  stdin  b'Ada\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'Hello, Ada!\n'
  t+ 3.01s  exit   b'0'
first output byte at t+0.31s.
```

## B: the answer is readable at t+0, but end of file comes at t+3

This tells "waits for the answer" apart from "waits for end of file":

```
L0 (limits/04):
  t+ 0.00s  stdin  b'Ada\n'
  t+ 3.01s  eof    b''
  t+ 3.01s  stdout b'What is your name? Hello, Ada!\n'
  t+ 3.01s  exit   b'0'
first output byte at t+3.01s.

sh reference:
  t+ 0.00s  stdin  b'Ada\n'
  t+ 0.02s  stdout b'What is your name? '
  t+ 0.02s  stdout b'Hello, Ada!\n'
  t+ 0.02s  exit   b'0'
first output byte at t+0.02s.
```

The L0 program's first byte appears when stdin closes, in both cases. Section
9 calls `main` only after end of file and writes only after `main` returns.
The language cannot move that, because section 6 has no builtin that writes
or reads. `tools/l0check` says so for the code that should have been
possible, [hypothetical/04](../hypothetical/04-no-output-before-eof.l0):

```
programs/hypothetical/04-no-output-before-eof.l0:10:15: error: unknown function 'write_stdout'
```

This reproduces the measurement already recorded in `spec/changelog.md`
("Output before input is an accepted blocker"), with a harness in this
repository.
