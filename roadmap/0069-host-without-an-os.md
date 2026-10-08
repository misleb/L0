# 0069: the spec says what a host without an operating system gives

Kind: language
Status: queued
Needs: nothing

## Why

[0068](0068-route-to-bare-metal.md) ran this program on QEMU's virt board,
with no operating system, through `roadmap/0068/metal.ll`:

```
(def main ((input (list int))) (list int)
  (let t0 (clock_ns)
    (let s (spin 10000000)
      (let t1 (clock_ns)
        (append (line (digits (sub t1 t0)))
          (append (line (digits (arg_count)))
            (line (digits (open_read (cons 120 (nil int)))))))))))
```

```
$ sh roadmap/0068/run.sh tmp/0068/progs/host.elf
82380992
0
-3
```

Every line is plausible, and none is what the spec says, because the spec
does not say. Section 10.3 says the runtime "reaches the operating system
only by calling libc", which a board cannot do. Section 6.3 has a code for a
missing file, but not for a host with no files at all, so `open_read` gives
-3 only because `access` failed, and `open_write` gives whatever the runtime
makes of a failed `creat` with no errno. Section 6.2's standard error is
assumed to be a separate stream; on a board with one serial line it is
semihosting, which real hardware lacks. And `L0_STACK_MB`, `L0_RC_CHECK`,
and `L0_ARRAY_STATS` come from an environment the board does not have.

6.4 already holds there: no arguments is `(arg_count)` 0.

## Done when

- the checklist in the `l0-bootstrap` skill, for a change to the spec alone
- 10.3 names the host interface the runtime calls, in place of libc, and
  says libc is behind it where there is an operating system
- 6.3 says what every file operation returns on a host without files, as a
  case the checker knows, and whether that is an existing code or a new one
- 6.2 and section 9 say where standard error and the exit status go when
  the host has one channel, or that a host must have two
- 10.3 says what the environment-variable settings become on a host
  without an environment
- no program's behavior changes on macOS or Linux

## Log

- 2026-10-08: opened by 0068's recommendation, item 1.
