; boot.ll -- arm64's part of a board's host: what runtime/bare/board.ll asks
; of the CPU, for any arm64 board. It boots the CPU by the arm64 boot
; protocol (spec section 10.3), takes its exceptions, runs a thread at EL0
; and takes its traps, writes arm64's page descriptors, and drives the
; generic timer. It names its triple, since most of it is assembly.
;
; The protocol: a raw image with the protocol's header, entered at EL1 with
; the device tree's address in x0. The board's layout gives the stack, the
; bss, and the header's image size, and its part gives the boot map,
; @l0_board_boot_map, the MMU's first tables.
;
; A program runs at EL1, with interrupts masked, and may run threads at EL0
; in spaces of its own (spec section 6.13). An exception the runtime does
; not expect is a bug in it, and is reported on standard error, with the
; registers that say where, and stops with status 99.

target triple = "aarch64-unknown-none-elf"

; ------------------------------------------------------------------- boot

; The arm64 boot protocol's header (Linux's Documentation/arm64/booting): a
; branch past it, a text offset of 0x80000 from the base of RAM, the
; image's size with its bss, no flags, and the magic "ARM\x64". A loader
; that sees it enters at _start with the device tree's address in x0.
;
; The boot code enables floating point and SIMD, which LLVM may use for
; copies, and the MMU, with the board's boot map at level 1 (TCR T0SZ 32,
; a 4 GB address space, 4 KB granule; MAIR attribute 0 Device-nGnRnE and 1
; normal write-back). It also lets EL0 read the virtual counter, and sets
; the SCTLR bits that let it read CTR_EL0 and zero by cache line, which LLVM
; may emit for a thread. Then it zeroes the bss and calls l0_bare_main with
; the device tree and CPU 0.
module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  b l0_aarch64_boot"
module asm "  .word 0"
module asm "  .quad 0x80000"
module asm "  .quad __image_size"
module asm "  .quad 0"
module asm "  .quad 0, 0, 0"
module asm "  .word 0x644d5241"
module asm "  .word 0"
module asm "l0_aarch64_boot:"
module asm "  mov x20, x0"
module asm "  mov x0, #(3 << 20)"
module asm "  msr cpacr_el1, x0"
module asm "  isb"
module asm "  ldr x0, =__stack_top"
module asm "  mov sp, x0"
module asm "  ldr x0, =l0_aarch64_vectors"
module asm "  msr vbar_el1, x0"
module asm "  mov x0, #3"
module asm "  msr cntkctl_el1, x0"
module asm "  mov x0, #0xff00"
module asm "  msr mair_el1, x0"
module asm "  ldr x0, =0x803520"
module asm "  msr tcr_el1, x0"
module asm "  ldr x0, =l0_board_boot_map"
module asm "  msr ttbr0_el1, x0"
module asm "  isb"
module asm "  tlbi vmalle1"
module asm "  dsb nsh"
module asm "  isb"
module asm "  mrs x0, sctlr_el1"
module asm "  ldr x1, =0x400D005"
module asm "  orr x0, x0, x1"
module asm "  bic x0, x0, #2"
module asm "  msr sctlr_el1, x0"
module asm "  isb"
module asm "  ldr x1, =__bss_start"
module asm "  ldr x2, =__bss_end"
module asm "4:"
module asm "  cmp x1, x2"
module asm "  b.hs 5f"
module asm "  str xzr, [x1], #8"
module asm "  b 4b"
module asm "5:"
module asm "  mov x0, x20"
module asm "  mov x1, #0"
module asm "  bl l0_bare_main"
module asm "1: b 1b"

; An exception at EL1 is the runtime's own bug. From EL0, at 0x400 (a
; synchronous exception: a system call or a fault) and 0x480 (an IRQ), it
; is a thread's trap, and ends its l0_aarch64_user_enter.
module asm ".balign 2048"
module asm "l0_aarch64_vectors:"
module asm ".rept 8"
module asm ".balign 128"
module asm "  b l0_aarch64_trap_entry"
module asm ".endr"
module asm ".balign 128"
module asm "  b l0_aarch64_user_sync"
module asm ".balign 128"
module asm "  b l0_aarch64_user_irq"
module asm ".rept 6"
module asm ".balign 128"
module asm "  b l0_aarch64_trap_entry"
module asm ".endr"
module asm "l0_aarch64_trap_entry:"
module asm "  mrs x0, esr_el1"
module asm "  mrs x1, elr_el1"
module asm "  mrs x2, far_el1"
module asm "  bl l0_aarch64_trap"
module asm "2: b 2b"

; l0_aarch64_user_enter(words, ttbr): saves what its caller expects kept
; (x19 to x30, d8 to d15) on this stack, records the stack and the
; context's words, switches to the thread's space, loads its registers from
; the words, and erets to EL0. Spec section 10.3 lays the words out, in
; bytes: x0 to x30 at 0, sp 248, pc 256, pstate 264, tpidr_el0 272, the
; trap's kind 280, its syndrome 288 and address 296, q0 to q31 from 304,
; fpcr 816, fpsr 824.
module asm ".text"
module asm ".global l0_aarch64_user_enter"
module asm "l0_aarch64_user_enter:"
module asm "  sub sp, sp, #176"
module asm "  stp x19, x20, [sp, #0]"
module asm "  stp x21, x22, [sp, #16]"
module asm "  stp x23, x24, [sp, #32]"
module asm "  stp x25, x26, [sp, #48]"
module asm "  stp x27, x28, [sp, #64]"
module asm "  stp x29, x30, [sp, #80]"
module asm "  stp d8, d9, [sp, #96]"
module asm "  stp d10, d11, [sp, #112]"
module asm "  stp d12, d13, [sp, #128]"
module asm "  stp d14, d15, [sp, #144]"
module asm "  adrp x9, l0_aarch64_user_sp"
module asm "  mov x10, sp"
module asm "  str x10, [x9, :lo12:l0_aarch64_user_sp]"
module asm "  adrp x9, l0_aarch64_user_ctx"
module asm "  str x0, [x9, :lo12:l0_aarch64_user_ctx]"
module asm "  msr ttbr0_el1, x1"
module asm "  isb"
module asm "  ldr x10, [x0, #248]"
module asm "  msr sp_el0, x10"
module asm "  ldr x10, [x0, #256]"
module asm "  msr elr_el1, x10"
module asm "  ldr x10, [x0, #264]"
module asm "  msr spsr_el1, x10"
module asm "  ldr x10, [x0, #272]"
module asm "  msr tpidr_el0, x10"
module asm "  ldr x10, [x0, #816]"
module asm "  msr fpcr, x10"
module asm "  ldr x10, [x0, #824]"
module asm "  msr fpsr, x10"
module asm "  add x1, x0, #304"
module asm "  ldp q0, q1, [x1, #0]"
module asm "  ldp q2, q3, [x1, #32]"
module asm "  ldp q4, q5, [x1, #64]"
module asm "  ldp q6, q7, [x1, #96]"
module asm "  ldp q8, q9, [x1, #128]"
module asm "  ldp q10, q11, [x1, #160]"
module asm "  ldp q12, q13, [x1, #192]"
module asm "  ldp q14, q15, [x1, #224]"
module asm "  ldp q16, q17, [x1, #256]"
module asm "  ldp q18, q19, [x1, #288]"
module asm "  ldp q20, q21, [x1, #320]"
module asm "  ldp q22, q23, [x1, #352]"
module asm "  ldp q24, q25, [x1, #384]"
module asm "  ldp q26, q27, [x1, #416]"
module asm "  ldp q28, q29, [x1, #448]"
module asm "  ldp q30, q31, [x1, #480]"
module asm "  ldp x2, x3, [x0, #16]"
module asm "  ldp x4, x5, [x0, #32]"
module asm "  ldp x6, x7, [x0, #48]"
module asm "  ldp x8, x9, [x0, #64]"
module asm "  ldp x10, x11, [x0, #80]"
module asm "  ldp x12, x13, [x0, #96]"
module asm "  ldp x14, x15, [x0, #112]"
module asm "  ldp x16, x17, [x0, #128]"
module asm "  ldp x18, x19, [x0, #144]"
module asm "  ldp x20, x21, [x0, #160]"
module asm "  ldp x22, x23, [x0, #176]"
module asm "  ldp x24, x25, [x0, #192]"
module asm "  ldp x26, x27, [x0, #208]"
module asm "  ldp x28, x29, [x0, #224]"
module asm "  ldr x30, [x0, #240]"
module asm "  ldp x0, x1, [x0, #0]"
module asm "  eret"

; A trap from EL0: x0 and x1 go below the stack, x1 says which kind, every
; register is saved into the words, with the syndrome and address of an
; exception, and l0_aarch64_user_enter returns to its caller.
module asm "l0_aarch64_user_sync:"
module asm "  stp x0, x1, [sp, #-16]!"
module asm "  mov x1, #0"
module asm "  b l0_aarch64_user_save"
module asm "l0_aarch64_user_irq:"
module asm "  stp x0, x1, [sp, #-16]!"
module asm "  mov x1, #1"
module asm "l0_aarch64_user_save:"
module asm "  adrp x0, l0_aarch64_user_ctx"
module asm "  ldr x0, [x0, :lo12:l0_aarch64_user_ctx]"
module asm "  stp x2, x3, [x0, #16]"
module asm "  stp x4, x5, [x0, #32]"
module asm "  stp x6, x7, [x0, #48]"
module asm "  stp x8, x9, [x0, #64]"
module asm "  stp x10, x11, [x0, #80]"
module asm "  stp x12, x13, [x0, #96]"
module asm "  stp x14, x15, [x0, #112]"
module asm "  stp x16, x17, [x0, #128]"
module asm "  stp x18, x19, [x0, #144]"
module asm "  stp x20, x21, [x0, #160]"
module asm "  stp x22, x23, [x0, #176]"
module asm "  stp x24, x25, [x0, #192]"
module asm "  stp x26, x27, [x0, #208]"
module asm "  stp x28, x29, [x0, #224]"
module asm "  str x30, [x0, #240]"
module asm "  ldp x2, x3, [sp], #16"
module asm "  stp x2, x3, [x0, #0]"
module asm "  mrs x2, sp_el0"
module asm "  str x2, [x0, #248]"
module asm "  mrs x2, elr_el1"
module asm "  str x2, [x0, #256]"
module asm "  mrs x2, spsr_el1"
module asm "  str x2, [x0, #264]"
module asm "  mrs x2, tpidr_el0"
module asm "  str x2, [x0, #272]"
module asm "  str x1, [x0, #280]"
module asm "  mov x2, #0"
module asm "  mov x3, #0"
module asm "  cbnz x1, 3f"
module asm "  mrs x2, esr_el1"
module asm "  mrs x3, far_el1"
module asm "3:"
module asm "  str x2, [x0, #288]"
module asm "  str x3, [x0, #296]"
module asm "  mrs x2, fpcr"
module asm "  str x2, [x0, #816]"
module asm "  mrs x2, fpsr"
module asm "  str x2, [x0, #824]"
module asm "  add x3, x0, #304"
module asm "  stp q0, q1, [x3, #0]"
module asm "  stp q2, q3, [x3, #32]"
module asm "  stp q4, q5, [x3, #64]"
module asm "  stp q6, q7, [x3, #96]"
module asm "  stp q8, q9, [x3, #128]"
module asm "  stp q10, q11, [x3, #160]"
module asm "  stp q12, q13, [x3, #192]"
module asm "  stp q14, q15, [x3, #224]"
module asm "  stp q16, q17, [x3, #256]"
module asm "  stp q18, q19, [x3, #288]"
module asm "  stp q20, q21, [x3, #320]"
module asm "  stp q22, q23, [x3, #352]"
module asm "  stp q24, q25, [x3, #384]"
module asm "  stp q26, q27, [x3, #416]"
module asm "  stp q28, q29, [x3, #448]"
module asm "  stp q30, q31, [x3, #480]"
module asm "  adrp x9, l0_aarch64_user_sp"
module asm "  ldr x9, [x9, :lo12:l0_aarch64_user_sp]"
module asm "  mov sp, x9"
module asm "  ldp x19, x20, [sp, #0]"
module asm "  ldp x21, x22, [sp, #16]"
module asm "  ldp x23, x24, [sp, #32]"
module asm "  ldp x25, x26, [sp, #48]"
module asm "  ldp x27, x28, [sp, #64]"
module asm "  ldp x29, x30, [sp, #80]"
module asm "  ldp d8, d9, [sp, #96]"
module asm "  ldp d10, d11, [sp, #112]"
module asm "  ldp d12, d13, [sp, #128]"
module asm "  ldp d14, d15, [sp, #144]"
module asm "  add sp, sp, #176"
module asm "  ret"

@l0_board_boot_map = external global [4 x i64]

; Defined by runtime/bare/board.ll.
declare void @l0_bare_main(i64, i64) noreturn
declare void @l0_bare_put_hex(i64)
declare i64 @l0_host_write(i64, ptr, i64)
declare void @l0_host_exit(i64) noreturn

declare void @l0_aarch64_user_enter(ptr, i64)

; Read and written by l0_aarch64_user_enter and its trap path.
@l0_aarch64_user_ctx = global i64 0
@l0_aarch64_user_sp = global i64 0

@m_trap = private constant [29 x i8] c"l0: machine exception: esr = "
@m_elr = private constant [8 x i8] c", elr = "
@m_far = private constant [8 x i8] c", far = "
@m_nl = private constant [1 x i8] c"\0A"

define void @l0_aarch64_trap(i64 %esr, i64 %elr, i64 %far) noreturn {
entry:
  %a = call i64 @l0_host_write(i64 2, ptr @m_trap, i64 29)
  call void @l0_bare_put_hex(i64 %esr)
  %b = call i64 @l0_host_write(i64 2, ptr @m_elr, i64 8)
  call void @l0_bare_put_hex(i64 %elr)
  %c = call i64 @l0_host_write(i64 2, ptr @m_far, i64 8)
  call void @l0_bare_put_hex(i64 %far)
  %d = call i64 @l0_host_write(i64 2, ptr @m_nl, i64 1)
  call void @l0_host_exit(i64 99)
  unreachable
}

; Spec section 6.16: aarch64 is CPU 1.
define i64 @l0_host_machine() {
entry:
  ret i64 1
}

; ----------------------------------------------- semihosting, the barrier

define i64 @l0_arch_semihost(i64 %op, ptr %blk) {
entry:
  %r = call i64 asm sideeffect "hlt #0xf000", "={x0},{x0},{x1},~{memory}"(i64 %op, ptr %blk)
  ret i64 %r
}

define void @l0_arch_barrier() {
entry:
  call void asm sideeffect "dsb sy", "~{memory}"()
  ret void
}

; Waits for an interrupt, with them masked, as the program runs.
define void @l0_arch_wait() {
entry:
  call void asm sideeffect "dsb sy\0Awfi", "~{memory}"()
  ret void
}

; ------------------------------------------------- the counter and timer

; The generic timer's virtual count, and how many it counts a second.
define i64 @l0_arch_counter() {
entry:
  %cnt = call i64 asm sideeffect "isb\0Amrs $0, cntvct_el0", "=r"()
  ret i64 %cnt
}

define i64 @l0_arch_counter_hz() {
entry:
  %frq = call i64 asm "mrs $0, cntfrq_el0", "=r"()
  ret i64 %frq
}

; The virtual timer's compare value, which raises its interrupt once the
; count reaches it.
define void @l0_arch_timer_set(i64 %cval) {
entry:
  call void asm sideeffect "msr cntv_cval_el0, $0", "r"(i64 %cval)
  call void asm sideeffect "msr cntv_ctl_el0, $0\0Aisb", "r"(i64 1)
  ret void
}

define void @l0_arch_timer_off() {
entry:
  call void asm sideeffect "msr cntv_ctl_el0, $0\0Aisb", "r"(i64 0)
  ret void
}

; --------------------------------------------------------------- user mode
;
; Spec sections 6.13 and 10.3. Every user entry is a 4 KB page, not global,
; so it is tagged with the space's ASID, in TTBR0's bits 48 up.

; A table descriptor for the table at pa, and the address a descriptor
; holds.
define i64 @l0_arch_pte_table(i64 %pa) {
entry:
  %d = or i64 %pa, 3
  ret i64 %d
}

define i64 @l0_arch_pte_pa(i64 %d) {
entry:
  %pa = and i64 %d, 281474976706560
  ret i64 %pa
}

; A user page's descriptor for the frame at pa and perm, spec section 6.13:
; valid, a page, normal memory (MAIR attribute 1), inner shareable,
; accessed, not global; AP 01, read and write at EL0, or 11, read only;
; never executable at EL1 (PXN), and at EL0 (UXN) unless perm says so.
define i64 @l0_arch_pte_page(i64 %pa, i64 %perm) {
entry:
  %w = and i64 %perm, 1
  %x = and i64 %perm, 2
  %rw = icmp ne i64 %w, 0
  %ap = select i1 %rw, i64 3911, i64 4039
  %ex = icmp ne i64 %x, 0
  %xn = select i1 %ex, i64 9007199254740992, i64 27021597764222976
  %bits = or i64 %ap, %xn
  %d = or i64 %pa, %bits
  ret i64 %d
}

; A device's page at pa: device memory, MAIR attribute 0, read and write at
; EL0, never executable.
define i64 @l0_arch_pte_device(i64 %pa) {
entry:
  %d = or i64 %pa, 27021597764226115
  ret i64 %d
}

; What a space's new tables need before a walk can see them.
define void @l0_arch_tables_written() {
entry:
  call void asm sideeffect "dsb ishst", "~{memory}"()
  ret void
}

; What pages just mapped in the space with this ASID need: a walk never
; caches an invalid entry on arm64, so only that the stores are seen.
define void @l0_arch_mapped(i64 %asid) {
entry:
  call void asm sideeffect "dsb ishst\0Aisb", "~{memory}"()
  ret void
}

; The user page at va, unmapped in the space with this ASID, out of the TLB.
define void @l0_arch_tlb_page(i64 %asid, i64 %va) {
entry:
  %pg = lshr i64 %va, 12
  %as = shl i64 %asid, 48
  %x = or i64 %pg, %as
  call void asm sideeffect "dsb ishst\0Atlbi vae1is, $0\0Adsb ish\0Aisb", "r,~{memory}"(i64 %x)
  ret void
}

; Back on the boot map, with the whole TLB flushed, before a space's tables
; are given back.
define void @l0_arch_space_leave() {
entry:
  %boot = ptrtoint ptr @l0_board_boot_map to i64
  call void asm sideeffect "msr ttbr0_el1, $0\0Aisb\0Adsb ishst\0Atlbi vmalle1is\0Adsb ish\0Aisb", "r,~{memory}"(i64 %boot)
  ret void
}

; Cleans the data cache to the point of unification over [pa, pa + n), and
; then invalidates the instruction cache, so that bytes copied into a
; space can be run there.
define void @l0_arch_code_sync(i64 %pa, i64 %n) {
entry:
  %ctr = call i64 asm "mrs $0, ctr_el0", "=r"()
  %dl0 = lshr i64 %ctr, 16
  %dl = and i64 %dl0, 15
  %line = shl i64 4, %dl
  %mask = sub i64 0, %line
  %a0 = and i64 %pa, %mask
  %end = add i64 %pa, %n
  br label %loop
loop:
  %a = phi i64 [ %a0, %entry ], [ %a1, %body ]
  %more = icmp ult i64 %a, %end
  br i1 %more, label %body, label %done
body:
  call void asm sideeffect "dc cvau, $0", "r,~{memory}"(i64 %a)
  %a1 = add i64 %a, %line
  br label %loop
done:
  call void asm sideeffect "dsb ish\0Aic iallu\0Adsb ish\0Aisb", "~{memory}"()
  ret void
}

; Runs the thread whose context is the 104 words at words, in the space
; whose root table is root, until it traps. Only the flags of its pstate
; are its own: it runs at EL0t, with interrupts unmasked.
define void @l0_arch_user_run(ptr %words, i64 %root, i64 %asid) {
entry:
  %as = shl i64 %asid, 48
  %ttbr = or i64 %root, %as
  %pp = getelementptr i64, ptr %words, i64 33
  %ps = load i64, ptr %pp
  %flags = and i64 %ps, 4026531840
  store i64 %flags, ptr %pp
  call void @l0_aarch64_user_enter(ptr %words, i64 %ttbr)
  ret void
}
