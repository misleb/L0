# 0068: research: the route to running on bare metal

Kind: research
Status: active
Needs: nothing

## Why

The README's "On bare metal" goal, recorded in the changelog as "A new goal:
running on bare metal": an L0 program runs with no operating system beneath
its runtime, and the measure is the compiler compiling itself there to the
same bytes it produces under one.

No L0 program can show this limit with `tools/l0check`, because the checker
does not know where a program will run. The limit is in the runtime and the
tools: every compiled program links `runtime/l0rt.ll`, which calls 30 libc
functions, and `tools/l0` can only build an executable for the host.

## The question

What is the smallest sequence of bootstrapped changes from here to the
compiler's fixpoint on a machine with no operating system? Settle at least:

- **The machine.** Which one first, booted how. QEMU's aarch64 `virt` board
  matches this host and the Linux test image (PL011 serial, the generic
  timer, PSCI or semihosting to stop), against x86_64 or a real board. What
  `exit` with a status becomes, so that a test can read it.
- **The toolchain.** Whether `clang --target=aarch64-none-elf` with a linker
  script and `ld.lld` produces a bootable image from the IR the compiler
  emits today, unchanged. Neither `ld.lld` nor QEMU is installed here; the
  `tools/linux` image may be the place for them. Installing either needs
  the user's go-ahead.
- **The runtime.** For each of the 30 libc functions `runtime/l0rt.ll`
  declares, what replaces it: an allocator over a region the runtime owns
  for `malloc`, `realloc`, and `free`; the serial line for descriptors 0, 1,
  and 2; the timer for `clock_gettime`; the boot stack, and a limit for
  `@l0_stack_check` from the linker script, for the 512 MB thread and
  `L0_STACK_MB`; nothing for `signal` and `dlsym`. Whether that is a second
  runtime file beside `l0rt.ll` or one file with a host-specific part, and
  what section 10.3 then says, since it now says the runtime reaches the
  operating system only through libc.
- **What the spec says about a host without things.** Files, a file
  system, arguments, the environment, and whether standard error is
  distinct from standard output on one serial line. Sections 6.2 to 6.4 and
  6.7 assume a host that has them; each silence found is a spec item.
- **The measure.** How the compiler's source reaches it (over the serial
  line, about a megabyte, or linked into the image as the input), how the
  emitted IR comes back to compare against `bootstrap/stage2.ll`, how much
  memory that takes, and how long it takes under emulation. Whether
  `tools/test.sh --compiled` can run its programs the same way, so the
  differential suite holds there too.
- **What stays out.** Driving devices from L0 code, interrupts, and more
  than one core need the systems primitives the changelog's "The route to
  memory management and I/O" deferred. Say what program would earn them,
  but do not plan them here.

## Done when

- the Log has a finding answering each question above, with a prototype in
  `roadmap/0068/`: a hand-built image in which an L0 program, compiled by
  today's compiler and unchanged, writes to the serial line under an
  emulator and stops with a status the host can read
- a recommendation naming the first item, tooling or language, and the
  items after it in order, through the compiler's fixpoint on the emulated
  machine

## Log

- 2026-10-08: opened with the goal, at the user's request. Next: ask the
  user about installing `ld.lld` and QEMU, or putting them in the Linux test
  image, then build the prototype.
- 2026-10-08: the user installed `lld` and `qemu` from Homebrew. QEMU 11.1.2
  runs; `ld.lld` is blocked by the machine's endpoint security (killed,
  exit 137). Next: the user picks where linking happens, then the
  prototype.
- 2026-10-08: **linking in Docker works, and costs little.** Files in
  `tmp/0068/`, image `l0-link-proto:arm64` from `tmp/0068/link/Dockerfile`
  (Ubuntu 24.04 with `lld-18` only). Host clang compiles with
  `--target=aarch64-none-elf -c`; the container runs only `ld.lld` on native
  objects, through a bind mount of `tmp/0068`.
  - `boot/start.ll`, a boot stub in IR (stack, FP enabled, PL011 writes,
    semihosting `SYS_EXIT`), linked by `boot/link.ld` at 0x40080000, boots
    under `qemu-system-aarch64 -M virt -cpu cortex-a72 -nographic
    -semihosting -kernel`, prints `hi`, and exits 3, which the host reads.
    QEMU's run takes 0.14 s, start to exit
  - Timed with `/usr/bin/time -p`, real time: an empty `docker run --rm`
    takes 0.19 s; linking the stub takes 0.27 s; linking the stub with the
    seed compiled for the board (`stage2.o`, 785 KB, libc and runtime
    symbols left unresolved) takes 0.25 and 0.26 s. Through `docker exec`
    into one running container, 0.07 s for the stub and 0.09 s for the
    compiler. For comparison, `tools/l0 build` of a three-byte hello on the
    host takes 0.78 s
  - So the round trip is Docker starting a container, not the link. One
    link per build adds about a third to a hello build. A suite of about
    130 images should link in one container, kept running or given every
    image in one run, not one `docker run` per image
  - LTO has to stay on the host. The container's LLVM 18 cannot read the
    bitcode Homebrew's newer LLVM writes, so the runtime and program are
    optimized together on the host into one native object, and the
    container only places sections
  - The seed's IR compiled for `aarch64-none-elf` unchanged; clang's only
    complaint is that it set the triple the IR leaves empty, as section 10.2
    intends
  Next: a freestanding runtime prototype, so that a real compiled L0
  program, not the stub, boots and prints.
- 2026-10-08: **finding: the compiler reaches its fixpoint on bare metal,
  with `runtime/l0rt.ll` and the emitted IR both unchanged.** Prototype in
  `roadmap/0068/`: `metal.ll` (about 500 lines of IR) supplies the 30 libc
  functions `l0rt.ll` declares, and the boot code; `metal.ld` lays out the
  image; `build.sh` and `run.sh` build and boot one; `Dockerfile` is the
  linker image; `progs/` holds the programs below.
  - **The measure.** `bootstrap/stage2.ll`, built as an image, read
    `lib/prelude.l0` and `compiler/*.l0` (209,340 bytes) as standard input
    and wrote 1,275,883 bytes over the serial line. Byte-identical to the
    same seed's output on the host, and after the tag line, to
    `bootstrap/stage2.ll`. Reproduced from the copies in `roadmap/0068/`.
    5.07 s under QEMU's emulation, against 0.21 s and 36 MB natively
  - **What else ran**, each built by `build.sh` from `tools/l0 emit`
    output: `rev` (whole input, from a loaded file), `echo` (streaming;
    status 87, its byte count, read by the host), `err` (`l0: runtime
    error: tail of empty list` on standard error alone, status 70, no
    result written), `deep` (`stack exhausted`, status 70, on the 256 MB
    boot stack), `host` (the clock: 82 ms for 10^7 calls; `arg_count` 0;
    `open_read` of a file gives -3)
  - **What replaces libc**, in `metal.ll`. Standard output: the PL011
    serial port. Standard input: a file QEMU's loader puts at 0x50000000,
    its length in the word below, since a serial line has no end of input.
    Standard error and the exit status: semihosting, so the two outputs
    stay apart on a board with one serial line. Memory: power-of-two size
    classes with free lists over a fixed heap, never split or merged. The
    clock: the generic timer. The stack: `pthread_create` fails, so
    `l0rt.ll`'s own fallback runs the program on the boot stack at the size
    `getrlimit` reports. errno: `dlsym` finds nothing, so it reads as -1.
    Files, the environment, signals: every call fails or does nothing. The
    boot code turns on the MMU with an identity map, since with it off
    every access is to device memory, where an unaligned one faults
  - **The shim works by leaning on fallbacks.** The stack and errno paths
    of `l0rt.ll` were written for a host where a thread or `dlsym` might
    fail, not for this. A change to either would break the board without
    any host test noticing. That argues for `l0rt.ll` calling a small host
    interface of its own, with a libc file and a board file behind it,
    rather than a board file that imitates libc
  - **The spec is silent where it was expected to be.** With no file
    system, `open_read` gives -3, "no such file", which reads correctly;
    `open_write` gives whatever the runtime makes of a failed `creat` with
    no errno. Nothing in 6.3 says what a host without files is. 6.4 does
    not say whether a host may have no arguments, not even a program name
  - **Speed.** Emulation is about 24 times native here. Apple's hypervisor
    (`-accel hvf -cpu host`) boots the image and prints, but QEMU does not
    handle the semihosting call under it, so the image never stops. A
    status channel other than semihosting would let the suite run at
    nearly native speed
  - **Not measured:** the board's peak memory. The allocator can waste up
    to half of each block, and the compiler fit in the 1.4 GB heap
  - **Recommendation**, in order; queueing them is the user's call:
    1. language: the spec says what a host without an operating system
       gives. Section 10.3 names the host interface `l0rt.ll` uses in
       place of "calls libc"; 6.3 and 6.4 say what a host without files,
       arguments, or an environment returns; and where standard error goes
       when there is one channel. `progs/host.l0` is its Why
    2. language: `l0rt.ll` calls that host interface, with
       `runtime/host-libc.ll` behind it on macOS and Linux, and no change
       to any program's output. The differential suite is its check
    3. language: `runtime/host-virt.ll`, `metal.ll` made real, with an
       allocator that splits and merges, and `tools/l0 build --target
       virt` producing an image, linked in the container while the host's
       `ld.lld` is blocked
    4. tooling: `tools/test.sh --virt` runs the compiled suite under QEMU,
       linking every image in one container, and `tools/bootstrap.sh`
       checks the fixpoint there. Then the goal's measure is a test, not a
       prototype
    5. later, and only if the suite is too slow: an exit that does not
       need semihosting, so the hypervisor can run it
