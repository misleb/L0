# 0034: A clock

Kind: language
Status: done, changelog "A clock"; Linux runs owed
Needs: nothing

## Why

No L0 program can tell how long anything took, so every timing in this
repository was taken from outside the process, and finding where a program
spends its time meant building it several times:

- 0028's sort was cut off after each stage by `0028/text/exp/stage.l0`, one
  build per stage, each timed by the shell and subtracted from the next.
- 0028's mst did the same with three extra programs,
  `0028/algorithms/mst/bench/{load,sort,flat}_main.l0`.
- 0014's kvstore README: "No clock, so every timing comes from outside the
  program", and its per-operation times were one process per operation.

The smallest program that cannot be written, a program timing its own read:

```
(def main () int
  (let t0 (clock_ns)
    (let b (read_bytes 0)
      (let t1 (clock_ns)
        (let w (write_err (append (digits (div (sub t1 t0) 1000000))
                                  (append " ms to read " (append (digits (bytes_len b)) " bytes\n"))))
          0)))))
```

```
$ tools/l0 check phase.l0
phase.l0:4:11: error: unknown function clock_ns
```

## Done when

- the l0-bootstrap checklist: spec, changelog, compiler, tests, both suites,
  fixpoint, seed refreshed
- `(clock_ns)` reads a monotonic clock in nanoseconds, is an effect that
  section 8's order places, and is tested measuring a real wait
- the runtime reads it without anything that differs between macOS and
  Linux, as its header requires
- the shipped l0-code skill says how to time a phase

## Log

- 2026-09-30: opened at the user's choice, after the queue emptied with
  0033. The evidence is every phase timing in 0014 and 0028. Only
  durations have been needed, so it is one monotonic clock; a wall clock
  waits for a program that needs a date.
- 2026-09-30: done. Spec section 6.7, and section 8 names reading the
  clock beside I/O as what may not be moved or removed. The runtime calls
  `clock_gettime` with clock 4, `CLOCK_MONOTONIC_RAW` on both macOS (SDK
  `_time.h`) and Linux (`uapi/linux/time.h`); `CLOCK_MONOTONIC` is 6 and 1,
  and Linux's 6 is its coarse clock. The checker and emitter learned the
  name; nothing in the compiler uses it.
  - Tests: `tests/io/clock` (never negative, 100,000 readings never go
    back, and a read held up a second measures at least 900 ms), and three
    checker cases in `tests/compiler/check_errors`. The first version of
    the io test raced a freshly built binary's start, which on macOS can
    take a second, and failed once; it now waits for the program's "ready"
    through named pipes, as `tests/io/prompt.sh` does, and a program that
    does not measure the wait fails it.
  - The phase program above reports 1 to 2 ms for reading 10 MB, and
    about 1,005 ms when its input arrives a second late.
  - Both suites green (60 and 99), fixpoint holds, seed refreshed, and
    `tools/l0` rebuilt from the seed builds the phase program.
  - Docker was not running, so the Linux runs are owed with the others.
