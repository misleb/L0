# L0 roadmap

Goals: README.md, "What L0 aims to be". Not restated here.

Current focus: the memory-management and I/O goal is met by the language route
(changelog "The route to memory management and I/O"): streaming and file I/O,
arguments, reference counting, and guaranteed tail calls, and the gaps 0014
found in it are closed by 0018 to 0020. The arrays goal's release rule
(0023) and arrays (0024) are done, and 0028's programs with arrays chose
what followed them (0029, 0030, 0025, 0026). 0026 found that holding text
one byte per byte needs a packed type, and that adding builtins must first
stop breaking programs; 0031 and 0032 did both, and 0033 put bytes to use in
the library and the text programs. Type parameters came next (0035): data
types take them (0036), a program's types shadow the library's (0037), the
library declares Option and Result (0039), and functions take them (0038),
so the library's list helpers now take every element type (0040). 0041
found that a generic function could not compare its elements, and `eq` now
compares two values of any type (0042), which the library and the suite
now use (0043). The compiler and the prelude could use neither, since stage
0 still ran their source; 0044 found that only the tools required it, and
the tools no longer do (0045). The prelude has taken back the generic
definitions, which the compiler now calls (0046), and the compiler is
written with type parameters and `eq` throughout (0047). Left from 0041's
candidates, `compare` and function values wait for a program that needs
them. 0049 found that a program can tell I/O failures apart only by their
words or codes, which the checker cannot see, and opening a file now says
which failure it was as a case typed per kind of open (0050); renames,
removals, flushes, and closes now do too (0062), and reads keep codes. 0051
found that no map can be written once for every key type, since nothing
can hash a value of a type parameter. `hash` now gives any value a
specified integer (0052), and the prelude has a `(Map K V)` for every key
and value type (0053), which the compiler's pad table and the suite's graph
now use (0054). A persistent map and an ordered one wait for code that
needs them. Everything through 0054 has passed on Linux, 0056 needed no
run, and 0057, 0058, 0061, 0062, 0064, and 0066 have passed on arm64. 0055's third
round of programs found a copying bug in the map (0056) and three places
the runtime broke section 6.3 (0057), both fixed, and earned bitwise
operations (0058), which make its hash program 4.2 times faster, a delete
(0061), and typed failures beyond opening (0062), all done. 0059 found that
19 of 21 orderings here are structural, directly or by a key, so `compare`
is in (0064), and the library sorts by it (0065); function values
wait for an order no key expresses, and would need closures or a context
argument to serve it. 0060 found the sieve no longer needs bytes that
update, since 0058's bitset sieve runs to 10^8 in 0.57 s and 14 MB, and that
reading in blocks is what tee and the unpacker need. With a bounded read
(0066) and `write_bytes` copying blocks, 0055's tee copies 100 MB to four
outputs in 0.08 s, faster than the system's; updatable bytes wait. Every
item 0055 opened is now done. The review after 0066 found that renaming a
directory onto a file gave -9, against section 6.3, now fixed (0067), and
the queue is empty. A new goal, running on bare metal (changelog "A new
goal: running on bare metal"), is what comes next, and 0068 breaks it down.
Its prototype reached the compiler's fixpoint on QEMU's virt board with the
runtime and emitted IR unchanged, and that is now real: the spec says what
a host without an operating system gives (0069), the runtime calls a host
interface (0070), the board has a runtime and `l0 build --target virt`
(0071), and `tools/test.sh --virt` checks the fixpoint and runs the
compiled suite there (0072). An exit the hypervisor handles was dropped,
since emulation is little of that suite's time (0073). Driving devices from
L0 code, interrupts, and real hardware are left open by the goal, and wait
for a program that needs them; the queue is empty, and what comes next
goes back to the goals. The next goal is a microkernel written in L0
(changelog "A new goal: a microkernel written in L0"), which is the program
that earns driving devices, and 0074 broke it down. Its prototype ran the
compiler to its fixpoint as a process at EL0 under a kernel stub, with no
language change, and found an L0 kernel's loop copies a thread's context
on every trap when written plainly. From it, regions are done (0075): a
program on the board drives a device through its registers, and the PL011
driver 0074 could not write is a test; and an element of an array updates
in place through any function (0076), so the kernel's loop written plainly
no longer copies a context per trap. A program now runs as a process of a
kernel (0077): `l0 build --target proc` makes the image, the spec fixes the
system calls any kernel answers, and the compiler reaches its fixpoint as a
process under a test kernel in IR. User mode came next, ahead of the
timer and interrupts by the user's choice (0078): a program on the board
makes spaces and runs threads in them, and a kernel written in L0, in
`tests/virt/user`, runs the compiler as a process to the same bytes. With
the timer and interrupts (0079) it runs several processes, preempted, the
host driving the GIC behind builtins. A process calls its kernel's own
system calls (0080), and under that kernel a serial driver that is a
process writes what a client sends it, waiting for its device's
interrupt. 0074's language items are done; left are the kernel in a
project of its own and the measure as a test, after the two gaps 0074's
Log names: `l0 test` on the board, now done (0081), and process images a
kernel can read (0082), now done too: the toolchain writes a process's
image raw, as a kernel loads it. Before 0082, the board came to give
arguments by the arm64 boot protocol (0083), so a kernel is told at boot
what to do with its images, as the L0 kernel now tells its serial driver
where its device is. Both gaps are closed; what is left of 0074 is the
kernel in a project of its own (item 7) and the measure as a test (item 8).
That project, L0S, asked for a frame's address, so its kernel can give a
virtio device memory to DMA into, and has it (0084). Freed blocks now go
back to the host a chunk at a time (0085), so a heap without an operating
system beneath it can hold one shape of data and then another. L0S then
asked to give back spaces and frames, and a kernel now can, and unmap a
page (0086).

The user then asked for the hosts without an operating system to run on
QEMU's riscv64 virt board as well as its aarch64 one, organized so that
later boards, the VisionFive 2 and the Raspberry Pi 4, are less work.
0087 found what the riscv64 board gives and laid out the route: the host
in parts (0088), a builtin naming the CPU (0089) and the library over it
(0090), and the riscv64 board, its process host, and the tests on both
CPUs (0091), which found LLVM's RISC-V back end passing a tail call's
stack words wrong, so every L0 function is now `fastcc`. Both boards run
everything, the compiler's fixpoint and both kernels included. Left for
the VisionFive 2 and the Pi 4: their RAM in the user range, DMA that is not
cache-coherent, and the Pi 4's boot at EL2 (changelog, 0091's entry).
L0S then found that two maps holding the same entries were not `eq`, and
now they are: the library's map keeps a table its entries alone decide
(0092). L0S then asked for a process's image as an ELF, so a kernel can
map its code, rodata, and data each by its own permissions and size the
image from its headers, rather than a raw image capped at 4 MB and mapped
writable and executable throughout; this repository's three kernels take
raw images too and changed with it (0093). Now the toolchain writes the
ELF, the L0 kernel maps each segment by its flags and kills a process
that writes its code, and an image's bss may pass 4 MB. L0S's font tool
turns a circle only by 5 degrees, from a table of sines in fixed point, so
floating point is in (0094), and so are sin and cos in the library (0095). The queue is
empty; L0S can drop its table of sines. L0S then found its processes
confined to the virt boards' fixed 384 MB of frames, and asked for the
pool to be all the RAM the layout leaves, the input's pages with it once
read, and a count of what is left, and has them (0097): about 765 MB of
frames on aarch64 and 1.2 GB on riscv64, from 384 MB. The user then asked
for a Raspberry Pi 5 target (0098), which has no emulator and so cannot be
run here: its parts are built and linked, the shared changes it needs (entry
at EL2, a 39-bit translation, input by the device tree's initrd) run under
the virt suite, and a first run on a board is left to the user. L0S then
found its servers holding their peak heap, since nothing told a kernel a
heap page was free again, and a process's runtime now does, by call 12,
which a kernel may answer by freeing the page's frame or ignore (0099).
Its compositor could open only 30 windows over its life, since the
runtime's 64 regions were never given back, and `region_close` now gives
one back, telling a process's kernel by call 13 (0100). L0S then asked for
what a USB stack needs: the aarch64 virt board's PCIe ECAM and MMIO window
as regions (0101), the Pi 5's RP1 as one (0102), and a builtin that cleans
and invalidates a frame for the Pi's DMA, which is not coherent (0103), and
has all three; interrupts for its driver wait for a request of their own.
For its display driver, the Pi 5's HVS and the IOMMU in front of it are
regions too (0105), and `l0 card` forces HDMI's hotplug.

## Language queue

Changes to the language, strictly in order. At most one is active.

None.

## Other open items

None.

## Done and dropped

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
  Raspberry Pi 5"; no run on a board, whose first run's checks the Log lists
- [0099](0099-release-heap-pages.md) a process's runtime hands free heap
  pages back to its kernel — done, changelog "A process hands free heap
  pages back to its kernel"; passed on Linux arm64
- [0100](0100-region-close.md) a region can be closed — done, changelog
  "A region can be closed"; passed on Linux arm64
- [0101](0101-virt-pcie-regions.md) the aarch64 virt board's PCIe ECAM and
  MMIO window are regions — done, changelog "The aarch64 virt board's PCIe
  ECAM and MMIO window are regions"
- [0102](0102-pi5-rp1-region.md) the Raspberry Pi 5's RP1 is a region —
  done, changelog "The Raspberry Pi 5's RP1 is a region"; no run on a board
- [0103](0103-frame-sync.md) `frame_sync` — done, changelog "A frame's
  bytes made to agree between the CPU's caches and memory"; passed on
  Linux arm64; no run on a Pi
- [0104](0104-board-layout-sizes.md) a board program sizes its heap and
  stack, or brings its own layout — done, changelog "A board program sizes
  its heap and stack, or brings its own layout"
- [0105](0105-pi5-hvs-regions.md) the Raspberry Pi 5's HVS and its IOMMU
  are regions — done, changelog "The Raspberry Pi 5's HVS and its IOMMU
  are regions"; no run on a board
