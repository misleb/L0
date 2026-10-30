# L0 roadmap

## Goals

Each goal of README.md's "What L0 aims to be", not restated here, where it
stands, and the
items that carried it. The Done list below, and the changelog, have the
history; this table replaced a narrative of it on 2026-10-30 (0143).

| Goal | State | Items |
| --- | --- | --- |
| Compiles itself | met, and kept: the fixpoint is checked on every change, here and on both virt boards | 0003, 0027, 0044 to 0047, 0072 |
| Compiled, with no C in a program | met: the runtime is LLVM IR, libc only behind the OS host | 0001, 0003, 0004, 0070 |
| Memory management and I/O | met: streaming and file I/O, arguments, reference counting with release at last use, tail calls, typed failures | 0005, 0008 to 0010, 0015, 0018 to 0020, 0023, 0049, 0050, 0062, 0066 |
| General purpose: data and types | met so far: arrays, bytes, type parameters, `eq`, `hash`, `compare`, maps, floats, bits, named fields, functions as arguments | 0021, 0024, 0032, 0035 to 0043, 0051 to 0054, 0058, 0064, 0094, 0132, 0135 |
| On bare metal | met on QEMU's aarch64 and riscv64 virt boards and run on a 2 GB Raspberry Pi 5; the 4 to 16 GB Pi 5s not run | 0068 to 0072, 0087 to 0091, 0098, 0110 |
| A microkernel in L0 | met in `tests/virt/user/kernel.l0`, on both boards and a Pi 5; L0S is the kernel in a project of its own, and its requests open most items since 0084 | 0074 to 0086, 0093, 0099, 0100, 0115, 0121 |
| Written for agents | ongoing: the review of 2026-10-30 opened 0135 to 0147 | 0131, 0133, 0139, 0141 to 0144 |

Open within those goals, waiting for code that needs them: closures, a
persistent or ordered map, bytes that update in place, the Pi 5's PCIe and
display interrupts beyond those given, and the VisionFive 2 and Pi 4.

## Language queue

Changes to the language, strictly in order. At most one is active.

1. [0130](0130-map-shrink-hysteresis.md) a map shrinks well below where
   it grows — queued, left for now: hysteresis breaks spec 6.9's promise
   that a map's table depends only on its entries, and a trie that keeps
   it is the way if taken up

The order above is the review's suggestion; the user decides it.

## Other open items

From the review of 2026-10-30, each proposed and not started:

- [0141](0141-spec-split.md) tooling: the spec split into the language,
  the runtime, and the boards
- [0142](0142-spec-tables.md) tooling: the spec's normative lists as
  tables, after 0141
- [0145](0145-compiler-internals.md) tooling: the compiler's own structure,
  after 0135
- [0146](0146-runtime-structure.md) tooling: the runtime's structure, the
  default host stubs first
- [0147](0147-verification.md) tooling: CI on both CPUs, and the suite's
  own loose ends

## Done and dropped

- [0140](0140-string-tables.md) tooling: string literals as byte tables —
  done, changelog "A string literal is a table of its bytes"; the seed is
  40% smaller

- [0139](0139-hidden-copy-warning.md) tooling: the checker warns of an
  update that a later use makes copy — done, changelog "The compiler warns
  of the hidden whole copy"; found one in the examples

- [0144](0144-library-naming.md) tooling: the library's regions are
  called regions, under one naming rule, the old names kept as aliases —
  done, changelog "The library's regions are called regions"

- [0138](0138-short-circuit.md) `and` and `or` evaluate their second
  operand only when it matters — done, changelog "and and or evaluate
  their second operand only when it matters"; `err_and_strict` left the
  differential suite; both suites, the fixpoint, and `--virt` on both
  boards green; not run on macOS or a Pi 5

- [0137](0137-unboxed-wrappers.md) a one-field wrapper of a word is the
  word — done, changelog "A one-field wrapper of a word is the word";
  `hash` of one is its field's; the kernel's spaces are typed; both
  suites, the fixpoint, and `--virt` on both boards green; not run on
  macOS or a Pi 5

- [0136](0136-field-take-out.md) a field taken out for a function and put
  back in place — done, changelog "A field goes through a function and
  back in place"; also fixed the array form taking an element `g` still
  held; the kernel and `space_put` use it; both suites, the fixpoint, and
  `--virt` on both boards green; not run on macOS or a Pi 5

- [0135](0135-function-arguments.md) functions as arguments, by one copy
  of the callee per `def` passed — done, changelog "Functions as
  arguments, by one copy per function passed"; the compiler's lookups are
  the prelude's `find_by`; both suites, the fixpoint, and `--virt` on both
  boards green; not run on macOS or a Pi 5

- [0143](0143-stale-documents.md) tooling: the documents that disagreed
  with the code — done; no language change

- [0134](0134-let-if-sugar.md) a `let` of several bindings and an `if` of
  several tests, desugared in the parser — done, changelog "A let of
  several bindings, and an if of several tests"; the compiler does not use
  them yet

- [0133](0133-fmt.md) tooling: `l0 fmt`, the closing parens a dedent or
  the next declaration shows missing — done, changelog "l0 fmt adds the
  closing parens the indentation shows missing, and no language change
  for it"; all 241 L0 files in the repository come back byte-identical

- [0132](0132-named-fields.md) named fields: a constructor names its
  fields, `(.f e)` reads one and `(.f e v)` replaces it, in place by 6.5's
  rule — done, changelog "Named fields: a value's field read and replaced
  by name"; the compiler, the kernel, and the examples use them; both
  suites, the fixpoint, and `--virt` on both boards green; not run on a
  Pi 5. Left open there: the take-out form for a field holding an array or
  map, after 0134

- [0129](0129-fast-frame-zero.md) a frame zeroed a cache block at a time,
  by `dc zva` on aarch64 — done, changelog "A frame is zeroed a cache
  block at a time, by dc zva on aarch64"; measured on a Pi 5, where past
  the caches DRAM's write-back, about 1.5 GB/s, is the bound; not run on
  riscv64's half of `--virt`

- [0131](0131-whole-copy-trap.md) the hidden whole copy of a map or
  array, named in the skills, `lib/AGENTS.md`, the Map's comments, the
  examples, and spec 6.5 — done, changelog "The hidden whole copy, named
  where an agent will see it"; a checker warning left open

- [0128](0128-wide-user-range.md) a space has a high user range, 128 GB
  from 0x2000000000 — done, changelog "A space has a high user range,
  128 GB past the 4th gigabyte"; aarch64 `--virt` green; not run on a
  Pi 5 or riscv64's half of `--virt`

- [0127](0127-pi5-hvs-eof.md) the Pi 5's display interrupt controller,
  `disp_intr`, is a region, with its interrupt, 129 — done, changelog
  "The Raspberry Pi 5's display interrupt controller, disp_intr, is a
  region, with its interrupt"; aarch64 `--virt` green; not run on a Pi 5
  or riscv64's half of `--virt`

- [0126](0126-region-bytes.md) a region's bytes copied out as bytes, and
  bytes into a region — done, changelog "A region's bytes are copied out
  as bytes, and bytes into it"; aarch64 `--virt` green; not run on macOS,
  a Pi 5, or riscv64's half of `--virt`

- [0125](0125-pi5-sdio1.md) the Pi 5's SD host controller, `sdio1`, is a
  region, with its interrupt, 305 — done, changelog "The Raspberry Pi 5's
  SD host controller, sdio1, is a region, with its interrupt"; aarch64
  `--virt` green; not run on a Pi 5 or riscv64's half of `--virt`

- [0124](0124-heap-left.md) how much of its heap a program has left —
  done, changelog "A program can ask how much of its heap is left";
  aarch64 `--virt` green; not run on macOS, a Pi 5, or riscv64's half of
  `--virt`

- [0123](0123-idle-cpus-halt.md) idle CPUs halt, woken by the host's own
  SGI — done, changelog "Idle CPUs halt"; aarch64 `--virt` green; not run
  on a Pi 5, Linux, or riscv64's half of `--virt`

- [0122](0122-pi5-dma40-channel.md) the Pi 5's `dma40` channel 6 is a
  region, with its interrupt, 118 — done, changelog "The Raspberry Pi 5's
  dma40 channel 6 is a region, with its interrupt"; not run on a Pi 5

- [0121](0121-other-cpus.md) user threads on the other CPUs — done,
  changelog "Threads run on the other CPUs"; aarch64 `--virt` green
  under `-smp 4`; not run on a Pi 5, Linux, or riscv64's half of `--virt`

- [0120](0120-pi5-hdmi-regions.md) the Pi 5's HDMI0 mode set (controller,
  PHY, pixel valve, DDC) is regions — done, changelog "The Raspberry Pi
  5's HDMI0 mode set is regions"; not run on a Pi 5

- [0119](0119-board-reset.md) a program can restart its board — done,
  changelog "A program can restart its board"; aarch64 `--virt` green; not
  run on a Pi 5, Linux, or riscv64's half of `--virt`

- [0116](0116-pi5-pcie-interrupts.md) the Pi 5's PCIe interrupts, RP1's
  among them — done, changelog "The Raspberry Pi 5 gives PCIe's MSIs,
  RP1's among them"; run on a Pi 5: RP1's test bit as 161, and its GPIO
  bank as 162; riscv64's half of `--virt` not run here

- [0118](0118-pi5-firmware-reservations.md) research: does the Pi 5's
  frame pool include RAM the firmware keeps (L0S's request) — done: no;
  the firmware leaves its framebuffer out of `/memory`, and every
  reservation is below the image or outside `/memory`; no change

- [0117](0117-pi5-rp1-driver.md) program: a first RP1 driver, as a process
  on the Pi 5 — dropped: the user's microkernel project brings up RP1's
  USB by polling, and reports back what L0 cannot express

- [0115](0115-pi5-microkernel.md) program: an L0 microkernel and its
  processes on the Pi 5 — done: `tests/virt/user/kernel.l0` ran `release`,
  `sleeper`, and the serial driver there, after the driver stopped relying
  on QEMU's PL011 raising a transmit interrupt per byte

- [0110](0110-pi5-board-checks.md) program: the checks 0098 left for a
  Pi 5, run on one — done on a 2 GB board: RP1's and the HVS's regions,
  arguments (0112), standard input, the clock, `/memory`, the frame pool,
  user mode, `frame_sync` and DMA through the mailbox, the virtual timer's,
  the UART's, and the system timer's four interrupts, SYSTEM_OFF, BL31's
  pages; RP1 reads its chip ID once the controller is set (0113, 0114);
  the HVS reads after a boot with a monitor and hangs without. Not run:
  the 4, 8, and 16 GB models, which need a board this host does not have

- [0114](0114-pi5-rp1-window.md) make RP1 answer on the Pi 5 — done,
  changelog "RP1's window answers once the controller is set"; run on a
  Pi 5: RP1's chip ID, 0x20001927, read through the window
- [0113](0113-pi5-pcie-controller-region.md) the Pi 5's PCIe controller for
  RP1 is a region — done, changelog "The Raspberry Pi 5's PCIe controller
  for RP1 is a region"; run on a Pi 5: the link is up, and RP1's window
  still reads 0xdeaddead; riscv64's half of `--virt` not run here
- [0001](0001-shed-c-runtime-plan.md) research: how to shed the C runtime —
  done
- [0002](0002-runtime-in-l0.md) program: write the runtime in L0 — done, ten
  limits recorded
- [0003](0003-ir-runtime.md) link compiled programs against an IR runtime
  instead of C — done, changelog "The runtime is LLVM IR, and stack exhaustion
  is checked rather than caught"
- [0004](0004-retire-c-runtime.md) tooling: retire the C runtime files — done;
  C remains only in `stage0/`
- [0005](0005-memory-and-io-route.md) research: which route to memory
  management and I/O — done, the language route, changelog "The route to
  memory management and I/O"
- [0006](0006-ordinary-programs.md) program: write ordinary programs and
  record where L0 stops — done, seven limits and four spec findings
- [0007](0007-main-signature-check.md) checking enforces `main`'s signature —
  done, changelog "Checking a fragment still checks its main"
- [0008](0008-streaming-io.md) streaming standard input and output — done,
  changelog "Reading and writing as a program runs"
- [0009](0009-args-files-failure.md) arguments, files, and failure — done,
  changelog "Files, arguments, and names reserved for the standard library"
- [0012](0012-test-framework.md) tooling: a test framework in the standard
  library — done, changelog "A test framework, and no language change for it"
- [0010](0010-reference-counting.md) reclaim memory by reference counting —
  done, changelog "Memory is reclaimed by reference counting"
- [0013](0013-release-at-last-use.md) release a value at its last use —
  dropped; its blocker was the input list built before `main`, which no
  release rule can reduce
- [0011](0011-tail-calls.md) research: whether L0 guarantees tail calls —
  done, all of them, by musttail and padded arities
- [0015](0015-guarantee-tail-calls.md) guarantee every tail call — done,
  changelog "A tail call uses no stack"
- [0014](0014-programs-round-two.md) program: a second round of ordinary
  programs, to choose the next goal — done; nine programs, the ranking led
  to 0017 through 0021
- [0016](0016-linux-test-image.md) tooling: a local image for the Linux test
  runs — done, `tools/linux-test.sh`
- [0022](0022-library-reference.md) tooling: the standard library documents
  itself, and l0 init copies no reference — done, changelog "The standard
  library documents itself"
- [0017](0017-library-and-tool-fixes.md) tooling: library and tool fixes from
  0014 — done, changelog "Reading a line can report a failure, and no
  language change for it"
- [0018](0018-write-failures-reported.md) a program can learn that its writes
  failed — done, changelog "A program can learn that its writes failed"
- [0019](0019-append-and-rename.md) append to a file, and replace one whole —
  done, changelog "Appending to a file, and replacing one in a single step"
- [0020](0020-in-memory-handles.md) handles that read from and write to
  memory — done, changelog "Handles that read from and write to memory"
- [0021](0021-arrays-route.md) research: how L0 gets arrays, compact bytes,
  and in-place update — done; the release rule first (0023), then arrays
  (0024)
- [0023](0023-release-at-last-use.md) release a value at its last use — done,
  changelog "A value is released at its last use"
- [0024](0024-arrays.md) arrays — done, changelog "Arrays"
- [0025](0025-nested-array-update.md) updating an array held inside another
  without copying it — done, changelog "A row of an array of rows updates in
  place, written the natural way"; Linux run with 0044
- [0030](0030-borrow-read-only-parameters.md) read-only parameters — done,
  changelog "Read-only parameters"; Linux run with 0044
- [0029](0029-array-docs.md) say what arrays really cost — done, changelog
  "What updates an array in place, said correctly, and no language change
  for it"
- [0028](0028-programs-with-arrays.md) program: programs written with arrays
  — done; nine programs, all faster than Python, which chose 0029, 0030,
  0025, and 0026
- [0027](0027-faster-compiler.md) tooling: a faster compiler — done, changelog
  "Programs and the runtime are optimized together, and no language change
  for it"
- [0026](0026-packed-bytes.md) research: how L0 holds bytes one byte per byte
  — done; a packed type (0032), after 0031, then 0033
- [0031](0031-builtins-do-not-take-over.md) a new builtin does not take over
  a program's function — done, changelog "A new builtin does not take over a
  program's function"; Linux run with 0044
- [0032](0032-bytes.md) bytes held one byte per byte — done, changelog
  "Bytes, held one byte per byte"; Linux run with 0044
- [0033](0033-bytes-library-and-programs.md) tooling: the library reads into
  bytes, and the text programs use it — done, changelog "The library reads a
  whole input into bytes, and no language change for it"; Linux run with
  0044
- [0034](0034-clock.md) a clock — done, changelog "A clock"; Linux run with
  0044
- [0035](0035-type-parameters.md) research: how L0 gets type parameters —
  done; parametric data (0036), then library type names (0037), then
  parametric functions (0038)
- [0036](0036-parametric-data.md) data types take type parameters — done,
  changelog "Data types take type parameters"; Linux run with 0044
- [0037](0037-library-type-names.md) a program's types do not collide with
  the library's — done, changelog "A program's types shadow the library's,
  and Io names are no longer reserved"; Linux run with 0044
- [0039](0039-library-option-result.md) tooling: the library declares
  Option and Result — done, changelog "The library declares Option and
  Result, and no language change for it"
- [0038](0038-parametric-functions.md) functions take type parameters —
  done, changelog "Functions take type parameters"
- [0040](0040-library-list-helpers.md) the library's list helpers work at
  every element type — done, changelog "The library's list helpers take
  every element type, and no language change for it"
- [0041](0041-comparing-any-type.md) research: how L0 compares values of any
  type — done; `eq` on any type first (0042)
- [0042](0042-eq-any-type.md) `eq` compares two values of any type — done,
  changelog "`eq` compares two values of any type"
- [0043](0043-library-onto-eq.md) the library and the suite's programs use
  `eq` — done, changelog "The library compares with eq, and no language
  change for it"
- [0044](0044-compiler-free-of-stage0.md) research: how the compiler and the
  prelude stop being run by stage 0 — done; the tools first (0045), then
  0046 and 0047
- [0045](0045-tools-without-stage0.md) tooling: the tools stop running the
  compiler under stage 0 — done, changelog "The compiler's source is no
  longer run by stage 0, and no language change for it"; Linux run with
  0054, after a fix
- [0046](0046-prelude-generics.md) the prelude takes back the generic
  definitions — done, changelog "The prelude takes back the generic
  definitions, and no language change for it"
- [0047](0047-compiler-uses-generics.md) the compiler uses type parameters
  and eq — done, changelog "The compiler is written with type parameters
  and eq, and no language change for it"
- [0048](0048-examples-current.md) tooling: the examples show what L0 has
  gained since they were written — done
- [0049](0049-io-failure-names.md) research: whether I/O failures should be
  named cases rather than codes — done; typed failures for opening (0050)
  first
- [0050](0050-open-failures-named.md) tooling: opening a file says which
  failure it was, as a case the checker knows — done, changelog "Opening a
  file says which failure it was, and no language change for it"
- [0051](0051-hash-and-map.md) research: how L0 gets a hash and a map —
  done; `hash` (0052), then a library map (0053), then its users (0054)
- [0052](0052-hash-builtin.md) `hash` gives a value of any type a specified
  integer — done, changelog "`hash` gives a value of any type a specified
  integer"; Linux run with 0054
- [0053](0053-library-map.md) the prelude has a map for every key and value
  type — done, changelog "The prelude has a map for every key and value
  type"
- [0054](0054-map-users.md) tooling: the compiler and the suite use the
  library's map — done, changelog "The compiler and the suite keep their
  tables in the library's map, and no language change for it"
- [0055](0055-programs-round-three.md) program: a third round of ordinary
  programs — done; nine programs, which chose 0056 to 0063
- [0056](0056-map-remove-in-place.md) `map_remove` updates in place — done,
  changelog "Removing a key from a map no longer copies it, and no language
  change for it"
- [0057](0057-io-keeps-section-6-3.md) the runtime keeps section 6.3's
  promises — done, changelog "A broken pipe is a write failure, a closed
  standard handle is open on nothing, and -3 means nothing is there"; passed
  on Linux arm64
- [0058](0058-bitwise-operations.md) bitwise operations — done, changelog
  "Bitwise operations"; passed on Linux arm64
- [0061](0061-delete-a-file.md) delete a file — done, changelog "Deleting a
  file"; passed on Linux arm64
- [0062](0062-typed-rename-flush-close.md) rename, remove, flush, and close
  say which failure it was — done, changelog "Renaming, removing, flushing,
  and closing say which failure it was"; passed on Linux arm64
- [0063](0063-docs-and-tools-from-0055.md) tooling: the doc and tool
  findings of 0055 — done, changelog "A declaration that does not parse is
  reported once, and no language change for it"
- [0059](0059-compare-or-function-values.md) research: ordering a value of
  any type — done; `compare` (0064), then the library on it (0065);
  function values wait
- [0064](0064-compare.md) `compare` orders two values of any type — done,
  changelog "`compare` orders two values of any type"; passed on Linux arm64
- [0065](0065-library-on-compare.md) tooling: the library sorts and takes
  min and max of any type — done, changelog "The library sorts, and takes
  the min and max, of any type, and no language change for it"
- [0060](0060-bounded-reads-and-updatable-bytes.md) research: reading at
  most n bytes, and bytes that update in place — done; a bounded read
  (0066); updatable bytes wait
- [0066](0066-bounded-read.md) reading at most n bytes — done, changelog
  "Reading at most n bytes"; passed on Linux arm64
- [0067](0067-rename-directory-onto-file.md) renaming a directory onto a
  file is not -9 — done, changelog "Renaming a directory onto a file is not
  a missing directory"; passed on Linux arm64
- [0068](0068-route-to-bare-metal.md) research: the route to running on bare
  metal — done; the fixpoint holds on QEMU's virt board, and 0069 to 0073
  make it real
- [0069](0069-host-without-an-os.md) the spec says what a host without an
  operating system gives — done, changelog "What a host without an
  operating system gives"
- [0070](0070-runtime-host-interface.md) the runtime calls a host interface,
  with libc behind it — done, changelog "The runtime reaches its host
  through an interface of its own"; passed on Linux arm64
- [0071](0071-virt-board-runtime.md) a runtime for QEMU's virt board, and
  l0 build for it — done, changelog "A host without an operating system:
  QEMU's virt board"; passed on Linux arm64
- [0072](0072-virt-test-suite.md) tooling: the compiled suite and the
  fixpoint run on the virt board — done, changelog "The fixpoint and the
  compiled suite run on the virt board, and no language change for it"
- [0073](0073-exit-without-semihosting.md) an exit that works under the
  hypervisor — dropped; emulation is little of the suite's time
- [0074](0074-route-to-a-microkernel.md) research: the route to a
  microkernel written in L0 — done; the compiler reaches its fixpoint as a
  process, and 0075 to 0077 come first
- [0075](0075-regions.md) regions: device memory, read and written by width
  — done, changelog "Regions: a program reads and writes a device's
  memory"; passed on Linux arm64
- [0076](0076-row-updates-through-any-function.md) an element of an array
  updates in place through any function — done, changelog "An element of
  an array updates in place through any function"; passed on Linux arm64
- [0077](0077-host-for-processes.md) a host for programs run as processes by
  a kernel — done, changelog "A host for programs run as processes by a
  kernel"
- [0078](0078-user-mode.md) user mode: address spaces, frames, and running a
  thread until it traps — done, changelog "User mode: address spaces,
  frames, and running a thread until it traps"; passed on Linux arm64
- [0079](0079-timer-and-interrupts.md) a timer deadline, interrupts, and
  waiting for one — done, changelog "Interrupts: a timer deadline, and
  taking, waiting for, and ending one"; passed on Linux arm64
- [0080](0080-kernel-calls.md) a process's calls to its kernel's own system
  calls — done, changelog "A process calls its kernel's own system calls";
  passed on Linux arm64
- [0081](0081-test-on-the-board.md) tooling: l0 test on the virt board —
  done, changelog "l0 test runs on the virt board, and no language change
  for it"; passed on Linux arm64
- [0083](0083-board-arguments.md) the virt board gives arguments, by the
  arm64 boot protocol — done, changelog "The virt board gives arguments, by
  the arm64 boot protocol"; passed on Linux arm64
- [0082](0082-kernel-input.md) tooling: process images for a kernel's input
  — done, changelog "A process's image is raw, as its kernel loads it, and
  no language change for it"
- [0084](0084-frame-address.md) a frame's address, so a kernel can give a
  device memory — done, changelog "A frame's address, so a kernel can give
  a device memory"; passed on Linux arm64
- [0085](0085-freed-memory-back-to-the-host.md) freed blocks go back to the
  host, a chunk at a time — done, changelog "Freed blocks go back to the
  host, a chunk at a time"; passed on Linux arm64
- [0086](0086-free-spaces-and-frames.md) freeing spaces and frames, and
  unmapping a page — done, changelog "Freeing spaces and frames, and
  unmapping a page"; passed on Linux arm64
- [0087](0087-route-to-riscv64.md) research: the route to riscv64, and
  what QEMU's board gives — done
- [0088](0088-host-in-parts.md) tooling: a host without an operating
  system, in parts — done, changelog "A host without an operating system
  is made of parts, and no language change for it"
- [0089](0089-machine.md) `(machine)`, the CPU a program runs on — done,
  changelog "A program asks which CPU it runs on"; passed on Linux arm64
- [0090](0090-calls-over-machine.md) the library and the L0 kernel read a
  system call over `(machine)` — done, changelog "The library reads a
  system call wherever the CPU keeps it"
- [0091](0091-riscv64-virt-board.md) the riscv64 virt board, and the tests
  on both CPUs — done, changelog "The virt board and the process host on
  riscv64" and "Every L0 function has the fast calling convention"; passed
  on Linux arm64 and amd64
- [0092](0092-map-by-entries.md) two maps holding the same entries are
  the same value — done, changelog "Two maps holding the same entries are
  the same value"
- [0093](0093-elf-process-images.md) a process's image is an ELF, its
  segments mapped by permission — done, changelog "A process's image is
  an ELF, its segments mapped by their permissions"
- [0094](0094-floating-point.md) floating point: `float`, its literals, and
  its builtins — done, changelog "Floating point"; passed on Linux arm64
- [0095](0095-sin-and-cos.md) tooling: the library's sin and cos — done,
  changelog "The library has sine and cosine, and no language change for it"
- [0096](0096-float-sqrt.md) `float_sqrt` — done, changelog "Square root of
  a float"; passed on Linux arm64
- [0097](0097-board-memory.md) the virt boards' frames come from all the
  RAM the layout leaves, and `frame_free_count` — done, changelog "The virt
  boards' frames come from all the RAM the layout leaves"; passed on Linux
  arm64
- [0098](0098-raspberry-pi-5.md) the Raspberry Pi 5 — done, changelog "The
  Raspberry Pi 5"; first run on a board 2026-10-24 (UART, EL2 entry,
  firmware load by TFTP), the rest of the checks run by 0110 on a 2 GB
  board
- [0099](0099-release-heap-pages.md) a process's runtime hands free heap
  pages back to its kernel — done, changelog "A process hands free heap
  pages back to its kernel"; passed on Linux arm64
- [0100](0100-region-close.md) a region can be closed — done, changelog
  "A region can be closed"; passed on Linux arm64
- [0101](0101-virt-pcie-regions.md) the aarch64 virt board's PCIe ECAM and
  MMIO window are regions — done, changelog "The aarch64 virt board's PCIe
  ECAM and MMIO window are regions"
- [0102](0102-pi5-rp1-region.md) the Raspberry Pi 5's RP1 is a region —
  done, changelog "The Raspberry Pi 5's RP1 is a region"; run on a board:
  it opens, and reads RP1's chip ID once the PCIe controller is set
  (0113, 0114)
- [0103](0103-frame-sync.md) `frame_sync` — done, changelog "A frame's
  bytes made to agree between the CPU's caches and memory"; passed on
  Linux arm64; run on a Pi 5 (0110): a mailbox call through a frame,
  synced both ways, got the board and firmware revisions back
- [0104](0104-board-layout-sizes.md) a board program sizes its heap and
  stack, or brings its own layout — done, changelog "A board program sizes
  its heap and stack, or brings its own layout"
- [0105](0105-pi5-hvs-regions.md) the Raspberry Pi 5's HVS and its IOMMU
  are regions — done, changelog "The Raspberry Pi 5's HVS and its IOMMU
  are regions"; run on a Pi 5 (0110): they open, and the HVS reads only
  after a boot with a monitor on HDMI0
- [0106](0106-virt-pcie-interrupts.md) the aarch64 virt board gives PCIe's
  interrupts, INTx and MSI — done, changelog "The aarch64 virt board gives
  PCIe's interrupts, INTx and MSI"
- [0107](0107-bytes-slice-concat.md) `bytes_slice` and `bytes_concat` —
  done, changelog "Bytes are sliced and joined without a list"; passed on
  Linux arm64
- [0108](0108-pi5-boot-loop.md) tooling: `tools/pi5-run`, a Pi 5 boot loop from
  source to serial log — done; run on a board
- [0109](0109-pi5-uart-id-registers.md) the Pi 5's debug UART has no
  identification registers — done, changelog "The Pi 5's debug UART has no
  identification registers"; run on a Pi 5; riscv64's half of `--virt` not
  run here
- [0112](0112-pi5-boot-argument-order.md) the Pi 5's firmware puts its
  arguments first, so the program's follow a marker — done, changelog "The
  Raspberry Pi 5's firmware puts its arguments first"; run on a Pi 5;
  riscv64's half of `--virt` not run here
- [0111](0111-pi5-frame-pool.md) the Pi 5's frame pool, said to be one
  gigabyte on a 16 GB board — dropped: the board is 2 GB, and the pool is
  as the spec gives it
