# 0093: a process's image is an ELF, its segments mapped by permission

Kind: language
Status: active
Needs: nothing

## Why

L0S, the kernel's own project, asked for it in `l0-request-proc-elf.md` at
its root (uncommitted there on 2026-10-19). `l0 build --target proc` writes
a raw image (0082, changelog "A process's image is raw, as its kernel loads
it, and no language change for it"), and a raw image tells its kernel
nothing:

- **A fixed 4 MB cap.** `runtime/proc.ld` puts `__heap_start` at
  `0xC0400000` and asserts the image ends below it, because a kernel cannot
  tell where the bss ends. The compiler, the largest program here, is
  1.4 MB raw on both CPUs (`build/stage2-proc-*.img`, 2026-10-18); L0S's
  largest is 760 KB, and it expects an interpreter to approach the cap.
- **Every image page is readable, writable, and executable.** A kernel
  cannot tell code from data. `tests/virt/user/kernel.l0`'s `ensure` maps
  every page of a process from `0xC0000000` with `perm` 3, so a process
  that writes over its own code is not stopped. `space_map` already takes
  a `perm` (spec 6.13), so the L0 kernel could map each page by what it
  holds, if the image said; nothing new is needed from the language for
  that.
- **No CPU and no symbols.** A kernel cannot refuse an image built for the
  other CPU, and a fault address cannot be named without rebuilding.

0082 named the reason that would bring the ELF back: "a kernel that wants
an ELF's segments, for their permissions". L0S is that kernel, and so is
this repository's own once it maps by permission.

## The plan

The format is L0S's: a static ELF64, `ET_EXEC`, `EM_AARCH64` or
`EM_RISCV`, entry `_start` at `0xC0000000`, and three page-aligned
`PT_LOAD`s, text (`PF_R|PF_X`), rodata (`PF_R`), and data with the bss
(`PF_R|PF_W`, `p_memsz > p_filesz`), none writable and executable, the
headers in none of them. The heap starts at the first page after the data
segment's end and runs to `0xD8000000`; the stack and the kernel's range
are unchanged. `--target virt` stays raw.

What the request did not cover: this repository has three kernels, two
test links, and the fixpoint run that take raw process images, and each
must take the ELF in the same change that the driver starts writing it,
since `tools/bootstrap.sh --virt` runs the compiler as a process under the
IR harness.

- `tests/virt/user/kernel.l0` reads each image's bytes from standard input
  and maps them at `0xC0000000`, then maps any page up to `0xE8000000`
  that a process touches, readable, writable, and executable.
- `tests/virt/proc/harness/{aarch64,riscv64}/kernel.ll` have QEMU's loader
  put each image raw in a 4 MB slot (`boot.sh`, `force-raw=on`) and map
  the slot at `0xC0000000` and the heap from `0xC0400000`, in 2 MB blocks.
- `tests/virt/proc/harness/boot.sh` links `fault.ll` with `runtime/proc.ld
  --oformat binary`, and `tools/test.sh`'s `user_ir` links the harness IR
  for the L0 kernel the same way.

### Order of work

Spec first, as the `l0-bootstrap` skill orders it. The compiler does not
change and does not use anything new, so there is one bootstrapped step,
not two.

1. **Spec 10.3 and the changelog.** The address-space table and the
   paragraph from "The image is those bytes, raw" say what the ELF is, and
   that the heap starts at the page after the image. Settle, and say:
   - a kernel maps each segment with at least its permissions and may
     give more, so a kernel that maps everything readable, writable, and
     executable still runs every program, but a program may not rely on
     writing its code or rodata
   - whether the heap keeps a guaranteed size (L0S's first open question).
     Lean: yes, the layout asserts the image ends below `0xD0000000`,
     which keeps 128 MB of heap and puts the limit where a program learns
     it, at link time, not as an allocation failure on its first run
   - the 4 MB slots are the IR harness's limit, not the spec's

   Changelog: why ELF now, against 0082's entry; why three segments and no
   writable and executable one; why the heap moved.
2. **The kernels take both.** Each tells an ELF by `\x7fELF` and takes a
   raw image as now, so the suites stay green before the switch.
   - `kernel.l0`: read the whole image, check `ELFCLASS64`, little endian,
     `ET_EXEC`, the machine matching `(machine)`, and each `PT_LOAD`
     inside `0xC0000000` to the heap's top; copy each segment's file bytes
     and map its pages with `perm` 2, 0, or 1 by its flags; refuse any
     other image as it refuses one it cannot give memory to. Map the pages
     from the data segment's end on, as now, a page at a time as they are
     touched, but writable and not executable, so a fault in text or
     rodata ends the process.
   - the harness kernels, in IR: copy each `PT_LOAD`'s file bytes to its
     place in the slot and zero to `p_memsz`; keep mapping the slot whole,
     which 1 allows. The other choice, flattening the ELF in `boot.sh`,
     needs `llvm-objcopy`, which the linker container does not hold
     (`lld-18` only) and 0082 removed; the loader in IR also keeps the
     harness, which is not L0 code, checking the format the toolchain
     writes.
3. **The switch.** `runtime/proc.ld` gets `PHDRS` and the heap after the
   image, as the request sketches. A manifest variable (`T_LDFLAGS`)
   carries `--oformat binary` in `virt-*.target` and `-z max-page-size=4096`
   in `proc-*.target`, and `bare_link` uses it in both its paths, the
   `L0_VIRT_LD` one and the container one. An installed target already
   gets its manifest whole (`tools/targets.sh` copies it), so only the
   variable's description there and `load_target`'s reset of the `T_`
   variables (`tools/l0`) need it. `boot.sh`'s
   `fault.ll` link and `test.sh`'s `user_ir` drop `--oformat binary`.
4. **Raw out of the kernels.** Once every image is an ELF, the raw path in
   the three kernels goes, so they check what the spec says and no more.
5. **Tests.**
   - the header of a built proc image, for each CPU: `ET_EXEC`, the
     machine, the entry, and the three `PT_LOAD`s with their flags and an
     alignment of 4096, checked in `tools/test.sh --virt` with whatever
     reads ELF headers that the tools already have (`llvm-readelf` if
     `find_cc`'s LLVM has one; the container does not)
   - an IR process beside `fault.ll` that writes over its own code, which
     `kernel.l0` must kill; under the harness, which maps the slot
     writable, it is not run
   - an IR process with a bss over 4 MB, which the old layout's `ASSERT`
     refused, run under `kernel.l0`
   - an image for the other CPU, refused by `kernel.l0`
   - a `--target virt` image byte for byte what it was before 3, for each
     CPU, compared once by hand and logged here
6. **Words that say raw** about a process: `tools/l0`'s header comment
   (lines 32 and 54) and the comment in `bare_link`, `lib/AGENTS.md`
   (what `l0 init` copies), `tools/install.sh`, `runtime/bare/proc.ll`'s
   layout comment, the three kernels' comments, `boot.sh`, `bundle.sh`,
   and `run.sh`.
7. **Tell L0S** it is done, with the format as the spec now states it, so
   its kernel can drop raw.

L0S's second open question is settled already: both riscv64 manifests
build with `-mno-relax`, so nothing uses `__global_pointer$`, and the
`ALIGN(4096)` before the data segment cannot move `.sdata` out of its
reach.

## Done when

- the checklist in the `l0-bootstrap` skill; no seed refresh, since the
  compiler does not change
- `tools/test.sh`, `tools/test.sh --compiled`, and `tools/test.sh --virt`
  on both CPUs green, and `tools/bootstrap.sh --virt`'s fixpoint holding
  with the compiler run as an ELF process on both
- the tests in step 5 pass; no Linux run, since neither the runtime a
  hosted program links nor the emitter changes
- L0S boots its demo and passes `make test-virt` and `make e2e` with every
  program built this way, which is L0S's to run

## Log

- 2026-10-19: opened from L0S's request, queued at the user's request with
  nothing changed yet. The request names the layout, the driver, spec
  10.3, and the words; checking it against this repository found the
  three kernels and two links above that take raw images and must change
  with it, and that `space_map`'s `perm` already lets the L0 kernel map
  by permission. Next: step 1, the spec.
- 2026-10-19: started; step 1 done. Spec 10.3 lists the ELF subset, has a
  kernel give at least each segment's permissions, starts the heap at the
  page after the image, and keeps 128 MB of heap by ending the image below
  0xD0000000; changelog "A process's image is an ELF, its segments mapped
  by their permissions". The harness's 4 MB slots are left for its own
  comments, not the spec. Until step 3 the spec says what the toolchain
  does not yet do. Next: step 2, the three kernels taking both formats.
- 2026-10-19: step 2. The request's `PHDRS` sketch links as it says, with
  `-z max-page-size=4096`, on both CPUs (`tmp/0093/proc.ld` and an
  `L0_VIRT_LD` wrapper, `tmp/0093/elf-ld`): three `PT_LOAD`s at offsets
  0x1000, 0x6000, and 0x7000 for `tests/virt/stream.l0`, R E, R, and RW,
  `.got` in the data on aarch64, and a `PT_RISCV_ATTRIBUTES` on riscv64,
  which the kernels ignore. The harness kernels share
  `tests/virt/proc/harness/elf.ll`, which `boot.sh` links beside each:
  it checks the header and each `PT_LOAD`, moves the segments down into
  place in the slot, and zeroes their bss and the slot from the image's
  end, and the kernel starts the process at `e_entry`; a slot whose file
  is over 4 MB is refused by `boot.sh`, and an ELF it cannot load is not
  started. `tests/virt/user/kernel.l0` reads an image's first 64 bytes and,
  for an ELF, its program headers, maps each segment with its flags'
  `perm`, copies its file bytes in as they stream past, and skips the
  rest, so a refused image leaves the next in step; it maps demanded
  pages read and write only, and gives -5 to a read, receive, or arg into
  a page the process may not write. A raw image loads as before. Checked
  by hand on both CPUs: `stream` as an ELF matches its expectations under
  all three kernels; a probe that writes its own code
  (`tmp/0093/selfwrite-*.ll`) is killed by the L0 kernel with a
  permission fault, and exits 0 under the harness, which maps its slot
  writable; an image for the other CPU is not started; and a refused
  image beside a good one leaves the good one's input right. These become
  tests in step 5. Suites green: 65, 147, and `--virt` 279 passed, 88
  skipped, on both CPUs, as before; `tools/bootstrap.sh --virt`'s
  fixpoint holds on both boards, under both harness kernels, and under the
  L0 kernel, the compiler still raw. Next: step 3, the switch.
- 2026-10-19: step 3. `runtime/proc.ld` has the `PHDRS` and the heap after
  the image, and asserts the image ends below 0xD0000000. Each manifest
  has `T_LDFLAGS`, `--oformat binary` for the boards and `-z
  max-page-size=4096` for processes, described in `tools/targets.sh`;
  `bare_link`, `boot.sh`'s `fault.ll`, and `test.sh`'s `user_ir` link
  with it, and `load_target` resets it. `tools/l0 build --target proc`
  now writes, for `stream`, the same bytes step 2's draft did on both
  CPUs. `lld` leaves an empty segment out: `fault.ll` has one `PT_LOAD`.
  Board images are byte for byte as before for `stream` and the L0
  kernel on both CPUs. The compiler's ELF process image is 1.4 MB on
  aarch64 and 1.6 MB on riscv64, which has a `PT_RISCV_ATTRIBUTES`
  beside its three `PT_LOAD`s. Suites green: 65, 147, `--virt` 279
  passed, 88 skipped, with every process an ELF; `tools/bootstrap.sh
  --virt`'s fixpoint holds on both boards and as an ELF process under all
  three kernels. Words that still say a process's image is raw wait for
  step 6. Next: step 4, raw out of the kernels.
- 2026-10-19: step 4. `kernel.l0` refuses an image that is not an ELF, as
  it refuses one it cannot load, and its raw loader is gone; `elf.ll`
  gives -1 for one, so the harness kernels refuse it too, and the
  kernels', `boot.sh`'s, and `bundle.sh`'s comments no longer call an
  image raw. Checked on both CPUs with `stream` flattened by
  `llvm-objcopy -O binary`: each of the three kernels does not start it,
  and under the L0 kernel the ELF beside it still meets its
  expectations. Suites green: 65, 147, `--virt` 279 passed, 88 skipped;
  `tools/bootstrap.sh --virt`'s fixpoint holds on both boards and under
  all three kernels. Next: step 5, the tests.
