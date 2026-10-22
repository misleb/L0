; kernel.ll -- a kernel, hand-written in IR, for QEMU's aarch64 virt board,
; that runs L0 programs built with tools/l0 build --target proc as processes
; at EL0, each in an address space of its own, and answers the system calls
; spec section 10.3 fixes for them. It is the harness tools/test.sh --virt
; and tools/bootstrap.sh --virt test runtime/bare/proc.ll against, as
; tests/backend holds hand-written IR: not the kernel, which is to be L0,
; and the virt board's, since it drives the GIC. It began as roadmap 0074's
; prototype.
;
; It is shaped as an L0 kernel would be: one loop (k_main) that picks a
; process, returns to it with k_user_run, and handles the trap it comes back
; with, with interrupts masked throughout. k_user_run takes a context, a
; thread's registers as 102 words, and returns when the thread next traps,
; with the context updated and the reason in its result.
;
; Physical memory, with QEMU's -m 2G:
;   0x40080000  this image, its page tables and contexts in bss
;   0x4FF00000  the kernel's stack, 1 MB, growing down
;   0x4FFFFFF8  standard input's length, then its bytes at 0x50000000
;   0x58000000  process images, 4 MB apart, put there by QEMU's loader as
;               their files: slot 0 at 0x58000000, 1 at 0x58400000, 2 at
;               0x58800000. A slot is a process when its first word is not
;               0. Its ELF's segments are moved into place in its slot,
;               and the rest zeroed, by ../elf.ll.
;   0x5EFFFFF8  the length of slot 0's arguments, then their bytes at
;               0x5F000000, each ending in a NUL; the other slots have none
;   0x60000000  frames, 2 MB each, to 0xC0000000, given out as touched
;
; Every process sees (runtime/proc.ld, spec section 10.3):
;   0x00000000  to 0xBFFFFFFF, the kernel's identity map, EL1 only, never
;               executable at EL0
;   0xC0000000  its slot, 4 MB, mapped when it is made: its image, and
;               after it the start of its heap
;   0xC0400000  to 0xE8000000, the rest of its heap, and its stack, a 2 MB
;               block mapped the first time it is touched, by a fault or a
;               system call
;   0xE8000000  to 0xE8200000, its regions: 4 KB pages of device memory,
;               mapped in order by the region system call
; The level 2 and 3 entries are not global, and are tagged with the
; process's ASID, slot + 1, so switching is a write of TTBR0 and no flush.
;
; System calls (svc #0, the number in x8, arguments in x0 to x3, result in
; x0), as section 10.3 numbers them. Standard output is the serial port and
; standard error semihosting, as on the board; standard input is the bytes
; QEMU loaded, shared. There are no files, and slot 0 alone has arguments.
;
; Preemption: before each return to a process the virtual timer is set for
; a slice; its interrupt, PPI 27 through the GICv2, brings the process back
; to the kernel, which moves to the next. The run ends when slot 0's
; process ends, with its status, or 99 if it was killed. The kernel writes
; nothing of its own but a line on standard error for each process it
; kills, so a program run as slot 0 meets the board's expectations.

target triple = "aarch64-unknown-none-elf"

; ------------------------------------------------------------------- boot

; The MMU: TCR T0SZ 32, a 4 GB address space, 4 KB granule, 40-bit physical
; addresses, so a region page can map the PCIe ECAM at 0x4010000000; MAIR
; attribute 0 Device-nGnRnE and 1 normal write-back.
module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  mov x0, #(3 << 20)"
module asm "  msr cpacr_el1, x0"
module asm "  isb"
module asm "  ldr x0, =__stack_top"
module asm "  mov sp, x0"
module asm "  ldr x0, =k_vectors"
module asm "  msr vbar_el1, x0"
module asm "  mov x0, #3"
module asm "  msr cntkctl_el1, x0"
module asm "  mov x0, #0xff00"
module asm "  msr mair_el1, x0"
module asm "  ldr x0, =0x200803520"
module asm "  msr tcr_el1, x0"
module asm "  ldr x0, =k_boot_pt"
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
module asm "  bl k_main"
module asm "1: b 1b"

; Exceptions from EL1 are the kernel's own bugs; from EL0 at 0x400 (a
; synchronous exception: a system call or a fault) and 0x480 (an IRQ) they
; are a process's trap, and end its k_user_run.
module asm ".balign 2048"
module asm "k_vectors:"
module asm ".rept 8"
module asm ".balign 128"
module asm "  b k_panic_entry"
module asm ".endr"
module asm ".balign 128"
module asm "  b k_el0_sync"
module asm ".balign 128"
module asm "  b k_el0_irq"
module asm ".rept 6"
module asm ".balign 128"
module asm "  b k_panic_entry"
module asm ".endr"
module asm "k_panic_entry:"
module asm "  mrs x0, esr_el1"
module asm "  mrs x1, elr_el1"
module asm "  mrs x2, far_el1"
module asm "  bl k_panic"
module asm "2: b 2b"

; k_user_run(ctx): saves what the kernel's caller expects kept (x19 to x30,
; d8 to d15) on the kernel stack, records that stack and ctx, loads the
; thread's address space and registers from ctx, and erets to EL0.
;
; ctx, in 8-byte words: 0 to 30 x0 to x30, 31 sp, 32 pc, 33 pstate, 34
; ttbr0, 35 unused, 36 to 99 q0 to q31, 100 fpcr, 101 fpsr.
module asm ".text"
module asm ".global k_user_run"
module asm "k_user_run:"
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
module asm "  adrp x9, k_saved_sp"
module asm "  mov x10, sp"
module asm "  str x10, [x9, :lo12:k_saved_sp]"
module asm "  adrp x9, k_cur_ctx"
module asm "  str x0, [x9, :lo12:k_cur_ctx]"
module asm "  ldr x10, [x0, #272]"
module asm "  msr ttbr0_el1, x10"
module asm "  isb"
module asm "  ldr x10, [x0, #248]"
module asm "  msr sp_el0, x10"
module asm "  ldr x10, [x0, #256]"
module asm "  msr elr_el1, x10"
module asm "  ldr x10, [x0, #264]"
module asm "  msr spsr_el1, x10"
module asm "  ldr x10, [x0, #800]"
module asm "  msr fpcr, x10"
module asm "  ldr x10, [x0, #808]"
module asm "  msr fpsr, x10"
module asm "  add x1, x0, #288"
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

; A trap from EL0: x0 and x1 go below the kernel stack, x1 says which kind,
; everything is saved into the current ctx, and k_user_run returns, to its
; caller, the ESR for a synchronous exception or -1 for an IRQ.
module asm "k_el0_sync:"
module asm "  stp x0, x1, [sp, #-16]!"
module asm "  mov x1, #0"
module asm "  b k_save"
module asm "k_el0_irq:"
module asm "  stp x0, x1, [sp, #-16]!"
module asm "  mov x1, #1"
module asm "k_save:"
module asm "  adrp x0, k_cur_ctx"
module asm "  ldr x0, [x0, :lo12:k_cur_ctx]"
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
module asm "  mrs x2, fpcr"
module asm "  str x2, [x0, #800]"
module asm "  mrs x2, fpsr"
module asm "  str x2, [x0, #808]"
module asm "  add x3, x0, #288"
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
module asm "  cbnz x1, 3f"
module asm "  mrs x0, esr_el1"
module asm "  b 4f"
module asm "3:"
module asm "  mov x0, #-1"
module asm "4:"
module asm "  adrp x9, k_saved_sp"
module asm "  ldr x9, [x9, :lo12:k_saved_sp]"
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

@k_cur_ctx = global i64 0
@k_saved_sp = global i64 0

; The kernel's own map, as runtime/board/virt-aarch64.ll's: devices, then RAM.
@k_boot_pt = global [4 x i64] [i64 1025, i64 1073743621, i64 2147485445, i64 0], align 4096

@l1 = global [3 x [512 x i64]] zeroinitializer, align 4096
@l2 = global [3 x [512 x i64]] zeroinitializer, align 4096
@l3 = global [3 x [512 x i64]] zeroinitializer, align 4096
@ctx = global [3 x [102 x i64]] zeroinitializer, align 16
@state = global [3 x i64] zeroinitializer       ; 0 none, 1 runnable, 2 ended
@status = global [3 x i64] zeroinitializer
@killed = global [3 x i64] zeroinitializer
@pages = global [3 x i64] zeroinitializer       ; region pages mapped
@next_frame = global i64 1610612736              ; 0x60000000
@in_pos = global i64 0

@__stack_top = external global i8

declare i64 @k_user_run(ptr)

; ------------------------------------------------------- the machine, small

define internal void @k_sync() {
  call void asm sideeffect "dsb ish\0Aisb", "~{memory}"()
  ret void
}

define internal i64 @k_far() {
  %r = call i64 asm sideeffect "mrs $0, far_el1", "=r"()
  ret i64 %r
}

define internal i64 @k_frq() {
  %r = call i64 asm "mrs $0, cntfrq_el0", "=r"()
  ret i64 %r
}

define internal void @timer_arm(i64 %ticks) {
  call void asm sideeffect "msr cntv_tval_el0, $0", "r"(i64 %ticks)
  call void asm sideeffect "msr cntv_ctl_el0, $0\0Aisb", "r"(i64 1)
  ret void
}

define internal void @timer_off() {
  call void asm sideeffect "msr cntv_ctl_el0, $0\0Aisb", "r"(i64 0)
  ret void
}

define internal void @mmio_w32(i64 %a, i32 %v) {
  %p = inttoptr i64 %a to ptr
  store volatile i32 %v, ptr %p
  ret void
}

define internal i32 @mmio_r32(i64 %a) {
  %p = inttoptr i64 %a to ptr
  %v = load volatile i32, ptr %p
  ret i32 %v
}

; GICv2: the distributor at 0x08000000, the CPU interface at 0x08010000.
; Only PPI 27, the virtual timer, is enabled.
define internal void @gic_init() {
  call void @mmio_w32(i64 134217728, i32 1)                 ; GICD_CTLR
  call void @mmio_w32(i64 134217984, i32 134217728)         ; GICD_ISENABLER0, bit 27
  call void @mmio_w32(i64 134283268, i32 240)               ; GICC_PMR
  call void @mmio_w32(i64 134283264, i32 1)                 ; GICC_CTLR
  ret void
}

; ------------------------------------------------------------ semihosting

define internal i64 @semi(i64 %op, ptr %blk) {
  %r = call i64 asm sideeffect "hlt #0xf000", "={x0},{x0},{x1},~{memory}"(i64 %op, ptr %blk)
  ret i64 %r
}

define internal void @k_exit(i64 %status) noreturn {
entry:
  %blk = alloca [2 x i64], align 8
  store i64 131110, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  store i64 %status, ptr %p1
  %r = call i64 @semi(i64 24, ptr %blk)
  br label %hang
hang:
  br label %hang
}

@tt = private constant [4 x i8] c":tt\00"
@err_handle = internal global i64 -1

define internal i64 @semi_stderr() {
entry:
  %h = load i64, ptr @err_handle
  %have = icmp sge i64 %h, 0
  br i1 %have, label %done, label %open
open:
  %blk = alloca [3 x i64], align 8
  %p0 = ptrtoint ptr @tt to i64
  store i64 %p0, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  store i64 8, ptr %p1
  %p2 = getelementptr i64, ptr %blk, i64 2
  store i64 3, ptr %p2
  %n = call i64 @semi(i64 1, ptr %blk)
  store i64 %n, ptr @err_handle
  br label %done
done:
  %r = phi i64 [ %h, %entry ], [ %n, %open ]
  ret i64 %r
}

; Writes n bytes at buf to the host's standard error, and returns how many.
define internal i64 @err_write(ptr %buf, i64 %n) {
entry:
  %h = call i64 @semi_stderr()
  %blk = alloca [3 x i64], align 8
  store i64 %h, ptr %blk
  %q1 = getelementptr i64, ptr %blk, i64 1
  %bi = ptrtoint ptr %buf to i64
  store i64 %bi, ptr %q1
  %q2 = getelementptr i64, ptr %blk, i64 2
  store i64 %n, ptr %q2
  %unwritten = call i64 @semi(i64 5, ptr %blk)
  %wrote = sub i64 %n, %unwritten
  ret i64 %wrote
}

define internal void @say(ptr %s) #0 {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %p = getelementptr i8, ptr %s, i64 %i
  %c = load i8, ptr %p
  %i1 = add i64 %i, 1
  %more = icmp ne i8 %c, 0
  br i1 %more, label %loop, label %done
done:
  %w = call i64 @err_write(ptr %s, i64 %i)
  ret void
}

@hexd = private constant [16 x i8] c"0123456789abcdef"

define internal void @say_hex(i64 %v) {
entry:
  %buf = alloca [18 x i8]
  store i8 48, ptr %buf
  %xp = getelementptr [18 x i8], ptr %buf, i64 0, i64 1
  store i8 120, ptr %xp
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %sh0 = sub i64 15, %i
  %sh = mul i64 %sh0, 4
  %nib = lshr i64 %v, %sh
  %d = and i64 %nib, 15
  %dp = getelementptr [16 x i8], ptr @hexd, i64 0, i64 %d
  %c = load i8, ptr %dp
  %o = add i64 %i, 2
  %bp = getelementptr [18 x i8], ptr %buf, i64 0, i64 %o
  store i8 %c, ptr %bp
  %i1 = add i64 %i, 1
  %more = icmp ult i64 %i1, 16
  br i1 %more, label %loop, label %done
done:
  %w = call i64 @err_write(ptr %buf, i64 18)
  ret void
}

define internal void @say_dec(i64 %v) {
entry:
  %buf = alloca [20 x i8]
  br label %loop
loop:
  %n = phi i64 [ %v, %entry ], [ %q, %loop ]
  %i = phi i64 [ 20, %entry ], [ %i1, %loop ]
  %q = udiv i64 %n, 10
  %r = urem i64 %n, 10
  %c0 = add i64 %r, 48
  %c = trunc i64 %c0 to i8
  %i1 = sub i64 %i, 1
  %bp = getelementptr [20 x i8], ptr %buf, i64 0, i64 %i1
  store i8 %c, ptr %bp
  %more = icmp ne i64 %q, 0
  br i1 %more, label %loop, label %done
done:
  %sp = getelementptr [20 x i8], ptr %buf, i64 0, i64 %i1
  %len = sub i64 20, %i1
  %w = call i64 @err_write(ptr %sp, i64 %len)
  ret void
}

@m_panic = private constant [32 x i8] c"kernel: exception in the kernel\00"
@m_esr = private constant [8 x i8] c" esr = \00"
@m_elr = private constant [8 x i8] c" elr = \00"
@m_far = private constant [8 x i8] c" far = \00"
@m_nl = private constant [2 x i8] c"\0A\00"

define void @k_panic(i64 %esr, i64 %elr, i64 %far) noreturn {
  call void @say(ptr @m_panic)
  call void @say(ptr @m_esr)
  call void @say_hex(i64 %esr)
  call void @say(ptr @m_elr)
  call void @say_hex(i64 %elr)
  call void @say(ptr @m_far)
  call void @say_hex(i64 %far)
  call void @say(ptr @m_nl)
  call void @k_exit(i64 99)
  unreachable
}

define internal void @uart_put(i8 %c) {
entry:
  br label %wait
wait:
  %fr = load volatile i32, ptr inttoptr (i64 150994968 to ptr)
  %full = and i32 %fr, 32
  %busy = icmp ne i32 %full, 0
  br i1 %busy, label %wait, label %send
send:
  store volatile i8 %c, ptr inttoptr (i64 150994944 to ptr)
  ret void
}

; ------------------------------------------------------------ the tables

define internal ptr @slot_word(ptr %table, i64 %i) {
  %p = getelementptr [3 x i64], ptr %table, i64 0, i64 %i
  ret ptr %p
}

define internal ptr @ctx_of(i64 %i) {
  %p = getelementptr [3 x [102 x i64]], ptr @ctx, i64 0, i64 %i, i64 0
  ret ptr %p
}

define internal ptr @reg(i64 %i, i64 %r) {
  %p = getelementptr [3 x [102 x i64]], ptr @ctx, i64 0, i64 %i, i64 %r
  ret ptr %p
}

define internal i64 @image_pa(i64 %i) {
  %o = mul i64 %i, 4194304
  %a = add i64 1476395008, %o
  ret i64 %a
}

; ------------------------------------------------------------ memory

define internal void @zero_frame(i64 %pa) #0 {
entry:
  br label %loop
loop:
  %o = phi i64 [ 0, %entry ], [ %o1, %loop ]
  %a = add i64 %pa, %o
  %p = inttoptr i64 %a to ptr
  store i64 0, ptr %p
  %o1 = add i64 %o, 8
  %more = icmp ult i64 %o1, 2097152
  br i1 %more, label %loop, label %done
done:
  ret void
}

; A fresh 2 MB frame, zeroed, or 0 when there are none left.
define internal i64 @alloc_frame() {
entry:
  %f = load i64, ptr @next_frame
  %out = icmp uge i64 %f, 3221225472
  br i1 %out, label %none, label %take
none:
  ret i64 0
take:
  %f1 = add i64 %f, 2097152
  store i64 %f1, ptr @next_frame
  call void @zero_frame(i64 %f)
  ret i64 %f
}

; Maps the 2 MB block holding va, in slot i's heap and stack, if it is not
; mapped yet. False when va is not in them, or no frame is left.
define internal i1 @map_block(i64 %i, i64 %va) {
entry:
  %lo = icmp ult i64 %va, 3225419776
  %hi = icmp uge i64 %va, 3892314112
  %out = or i1 %lo, %hi
  br i1 %out, label %no, label %look
look:
  %off = sub i64 %va, 3221225472
  %idx = lshr i64 %off, 21
  %ep = getelementptr [3 x [512 x i64]], ptr @l2, i64 0, i64 %i, i64 %idx
  %e = load i64, ptr %ep
  %have = icmp ne i64 %e, 0
  br i1 %have, label %yes, label %new
new:
  %f = call i64 @alloc_frame()
  %none = icmp eq i64 %f, 0
  br i1 %none, label %no, label %put
put:
  %d = or i64 %f, 27021597764226885                         ; user data
  store i64 %d, ptr %ep
  call void @k_sync()
  br label %yes
yes:
  ret i1 true
no:
  ret i1 false
}

; Whether [va, va + n) is in slot i's image, heap, or stack, mapping what is
; not yet; the check a kernel must make before it touches a process's
; buffer, which in L0 would be a copy into or out of a space handle rather
; than an address. An empty range touches nothing, and is always in. va is
; bounded before va + n is formed, so the sum cannot wrap.
define internal i1 @user_range(i64 %i, i64 %va, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  %big = icmp ugt i64 %n, 1073741824
  %badn = or i1 %neg, %big
  br i1 %badn, label %no, label %empty
empty:
  %zero = icmp eq i64 %n, 0
  br i1 %zero, label %yes, label %bounds
bounds:
  %lo = icmp ult i64 %va, 3221225472
  %top = icmp ugt i64 %va, 3892314112
  %end = add i64 %va, %n
  %hi = icmp ugt i64 %end, 3892314112
  %out0 = or i1 %lo, %top
  %out = or i1 %out0, %hi
  br i1 %out, label %no, label %first
first:
  %last = sub i64 %end, 1
  %b0 = and i64 %va, -2097152
  br label %loop
loop:
  %b = phi i64 [ %b0, %first ], [ %b1, %next ]
  %img = icmp ult i64 %b, 3225419776
  br i1 %img, label %next, label %map
map:
  %ok = call i1 @map_block(i64 %i, i64 %b)
  br i1 %ok, label %next, label %no
next:
  %b1 = add i64 %b, 2097152
  %more = icmp ule i64 %b1, %last
  br i1 %more, label %loop, label %yes
yes:
  ret i1 true
no:
  ret i1 false
}

; ------------------------------------------------------------ processes

define internal void @make_proc(i64 %i) {
entry:
  %e0 = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 0
  store i64 27021597764224001, ptr %e0                      ; devices
  %e1 = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 1
  store i64 18014399583225605, ptr %e1                      ; RAM, EL1 only
  %e2 = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 2
  store i64 18014400656967429, ptr %e2
  %t = getelementptr [3 x [512 x i64]], ptr @l2, i64 0, i64 %i, i64 0
  %tpa = ptrtoint ptr %t to i64
  %td = or i64 %tpa, 3
  %e3 = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 3
  store i64 %td, ptr %e3
  %img = call i64 @image_pa(i64 %i)
  %pc0 = call i64 @elf_load(i64 %img, i64 183)              ; EM_AARCH64
  %c0 = or i64 %img, 9007199254744901                       ; user code
  store i64 %c0, ptr %t
  %img1 = add i64 %img, 2097152
  %c1 = or i64 %img1, 9007199254744901
  %t1 = getelementptr [3 x [512 x i64]], ptr @l2, i64 0, i64 %i, i64 1
  store i64 %c1, ptr %t1
  ; 0xE8000000, level 2 entry 320: the table of this process's regions
  %r = getelementptr [3 x [512 x i64]], ptr @l3, i64 0, i64 %i, i64 0
  %rpa = ptrtoint ptr %r to i64
  %rd = or i64 %rpa, 3
  %t320 = getelementptr [3 x [512 x i64]], ptr @l2, i64 0, i64 %i, i64 320
  store i64 %rd, ptr %t320
  %l1p = ptrtoint ptr %e0 to i64
  %asid = add i64 %i, 1
  %tag = shl i64 %asid, 48
  %ttbr = or i64 %l1p, %tag
  %r34 = call ptr @reg(i64 %i, i64 34)
  store i64 %ttbr, ptr %r34
  %r31 = call ptr @reg(i64 %i, i64 31)
  store i64 3892314112, ptr %r31                            ; sp, 0xE8000000
  %r32 = call ptr @reg(i64 %i, i64 32)
  store i64 %pc0, ptr %r32                                  ; pc, the entry
  %r33 = call ptr @reg(i64 %i, i64 33)
  store i64 0, ptr %r33                                     ; EL0t, unmasked
  %sp = call ptr @slot_word(ptr @state, i64 %i)
  store i64 1, ptr %sp
  call void @k_sync()
  %refused = icmp slt i64 %pc0, 0
  br i1 %refused, label %refuse, label %made
refuse:
  call void @refuse(i64 %i)
  br label %made
made:
  ret void
}

declare i64 @elf_load(i64, i64)

@m_refused = private constant [36 x i8] c" not started: not an image it loads\00"

; Slot i, whose image elf_load cannot load, ended as if killed.
define internal void @refuse(i64 %i) {
  call void @say(ptr @m_proc)
  call void @say_dec(i64 %i)
  call void @say(ptr @m_refused)
  call void @say(ptr @m_nl)
  call void @end_proc(i64 %i, i64 99, i64 1)
  ret void
}

define internal void @end_proc(i64 %i, i64 %st, i64 %kill) {
  %s = call ptr @slot_word(ptr @state, i64 %i)
  store i64 2, ptr %s
  %p = call ptr @slot_word(ptr @status, i64 %i)
  store i64 %st, ptr %p
  %k = call ptr @slot_word(ptr @killed, i64 %i)
  store i64 %kill, ptr %k
  ret void
}

@m_proc = private constant [17 x i8] c"kernel: process \00"
@m_killed = private constant [10 x i8] c" killed: \00"
@m_fault = private constant [6 x i8] c"fault\00"
@m_oom = private constant [14 x i8] c"out of memory\00"

define internal void @kill(i64 %i, i64 %esr) {
  %far = call i64 @k_far()
  %ep = call ptr @reg(i64 %i, i64 32)
  %pc = load i64, ptr %ep
  call void @say(ptr @m_proc)
  call void @say_dec(i64 %i)
  call void @say(ptr @m_killed)
  call void @say(ptr @m_fault)
  call void @say(ptr @m_esr)
  call void @say_hex(i64 %esr)
  call void @say(ptr @m_elr)
  call void @say_hex(i64 %pc)
  call void @say(ptr @m_far)
  call void @say_hex(i64 %far)
  call void @say(ptr @m_nl)
  call void @end_proc(i64 %i, i64 99, i64 1)
  ret void
}

define internal void @kill_oom(i64 %i) {
  call void @say(ptr @m_proc)
  call void @say_dec(i64 %i)
  call void @say(ptr @m_killed)
  call void @say(ptr @m_oom)
  call void @say(ptr @m_nl)
  call void @end_proc(i64 %i, i64 99, i64 1)
  ret void
}

; ------------------------------------------------------------ the streams

; read from standard input, the bytes QEMU loaded, into the process's buf.
define internal i64 @sys_read(i64 %i, i64 %s, i64 %buf, i64 %n) {
entry:
  %is0 = icmp eq i64 %s, 0
  br i1 %is0, label %check, label %bad
check:
  %ok = call i1 @user_range(i64 %i, i64 %buf, i64 %n)
  br i1 %ok, label %copy0, label %bad
copy0:
  %len = load i64, ptr inttoptr (i64 1342177272 to ptr)
  %pos = load i64, ptr @in_pos
  %left = sub i64 %len, %pos
  %less = icmp ult i64 %left, %n
  %k = select i1 %less, i64 %left, i64 %n
  br label %loop
loop:
  %j = phi i64 [ 0, %copy0 ], [ %j1, %body ]
  %more = icmp ult i64 %j, %k
  br i1 %more, label %body, label %done
body:
  %sa0 = add i64 1342177280, %pos
  %sa = add i64 %sa0, %j
  %sp = inttoptr i64 %sa to ptr
  %c = load i8, ptr %sp
  %da = add i64 %buf, %j
  %dp = inttoptr i64 %da to ptr
  store i8 %c, ptr %dp
  %j1 = add i64 %j, 1
  br label %loop
done:
  %np = add i64 %pos, %k
  store i64 %np, ptr @in_pos
  ret i64 %k
bad:
  ret i64 -5
}

define internal i64 @sys_write(i64 %i, i64 %s, i64 %buf, i64 %n) {
entry:
  %ok = call i1 @user_range(i64 %i, i64 %buf, i64 %n)
  br i1 %ok, label %which, label %bad
which:
  %is1 = icmp eq i64 %s, 1
  br i1 %is1, label %uart, label %not1
not1:
  %is2 = icmp eq i64 %s, 2
  br i1 %is2, label %err, label %bad
uart:
  br label %loop
loop:
  %j = phi i64 [ 0, %uart ], [ %j1, %body ]
  %more = icmp ult i64 %j, %n
  br i1 %more, label %body, label %sent
body:
  %a = add i64 %buf, %j
  %p = inttoptr i64 %a to ptr
  %c = load i8, ptr %p
  call void @uart_put(i8 %c)
  %j1 = add i64 %j, 1
  br label %loop
sent:
  ret i64 %n
err:
  %bp = inttoptr i64 %buf to ptr
  %w = call i64 @err_write(ptr %bp, i64 %n)
  %none = icmp sle i64 %w, 0
  %r = select i1 %none, i64 -5, i64 %w
  ret i64 %r
bad:
  ret i64 -5
}

; ------------------------------------------------------------ files

; Section 9.2's absence of files, as on the board: nothing to open, rename,
; or remove, and no directory to make a file in. Each path must still be
; the process's to read.
define internal i64 @sys_open(i64 %i, i64 %path, i64 %len, i64 %mode) {
entry:
  %ok = call i1 @user_range(i64 %i, i64 %path, i64 %len)
  br i1 %ok, label %none, label %bad
none:
  %rd = icmp eq i64 %mode, 1
  %r = select i1 %rd, i64 -3, i64 -9
  ret i64 %r
bad:
  ret i64 -5
}

define internal i64 @sys_no_file(i64 %i, i64 %a, i64 %an, i64 %b, i64 %bn) {
entry:
  %oka = call i1 @user_range(i64 %i, i64 %a, i64 %an)
  %okb = call i1 @user_range(i64 %i, i64 %b, i64 %bn)
  %ok = and i1 %oka, %okb
  %r = select i1 %ok, i64 -3, i64 -5
  ret i64 %r
}

; ------------------------------------------------------------ arguments

; Slot 0's arguments are the bytes at 0x5F000000, each ending in a NUL,
; and as many as the word below them says.
define internal i64 @args_len() {
  %n = load i64, ptr inttoptr (i64 1593835512 to ptr)
  ret i64 %n
}

; The offset of the NUL that ends the argument starting at o, or of the
; end of the bytes if none does.
define internal i64 @arg_end(i64 %o) {
entry:
  %len = call i64 @args_len()
  br label %loop
loop:
  %j = phi i64 [ %o, %entry ], [ %j1, %step ]
  %in = icmp ult i64 %j, %len
  br i1 %in, label %look, label %done
look:
  %a = add i64 1593835520, %j
  %p = inttoptr i64 %a to ptr
  %c = load i8, ptr %p
  %nul = icmp eq i8 %c, 0
  br i1 %nul, label %done, label %step
step:
  %j1 = add i64 %j, 1
  br label %loop
done:
  ret i64 %j
}

; The offset of argument k's first byte, or -1 if there is no argument k.
define internal i64 @arg_start(i64 %k) {
entry:
  %len = call i64 @args_len()
  br label %at
at:
  %o = phi i64 [ 0, %entry ], [ %next, %skip ]
  %seen = phi i64 [ 0, %entry ], [ %seen1, %skip ]
  %left = icmp ult i64 %o, %len
  br i1 %left, label %which, label %none
which:
  %this = icmp eq i64 %seen, %k
  br i1 %this, label %found, label %skip
skip:
  %e = call i64 @arg_end(i64 %o)
  %next = add i64 %e, 1
  %seen1 = add i64 %seen, 1
  br label %at
found:
  ret i64 %o
none:
  ret i64 -1
}

define internal i64 @sys_arg_count(i64 %i) {
entry:
  %first = icmp eq i64 %i, 0
  br i1 %first, label %count, label %zero
zero:
  ret i64 0
count:
  %len = call i64 @args_len()
  br label %loop
loop:
  %o = phi i64 [ 0, %count ], [ %next, %step ]
  %n = phi i64 [ 0, %count ], [ %n1, %step ]
  %left = icmp ult i64 %o, %len
  br i1 %left, label %step, label %done
step:
  %e = call i64 @arg_end(i64 %o)
  %next = add i64 %e, 1
  %n1 = add i64 %n, 1
  br label %loop
done:
  ret i64 %n
}

; Copies at most n bytes of argument k into the process's buf, and returns
; the argument's length.
define internal i64 @sys_arg(i64 %i, i64 %k, i64 %buf, i64 %n) {
entry:
  %first = icmp eq i64 %i, 0
  br i1 %first, label %find, label %bad
find:
  %o = call i64 @arg_start(i64 %k)
  %none = icmp slt i64 %o, 0
  br i1 %none, label %bad, label %check
check:
  %e = call i64 @arg_end(i64 %o)
  %len = sub i64 %e, %o
  %ok = call i1 @user_range(i64 %i, i64 %buf, i64 %n)
  br i1 %ok, label %copy0, label %bad
copy0:
  %less = icmp ult i64 %len, %n
  %m = select i1 %less, i64 %len, i64 %n
  br label %loop
loop:
  %j = phi i64 [ 0, %copy0 ], [ %j1, %body ]
  %more = icmp ult i64 %j, %m
  br i1 %more, label %body, label %done
body:
  %sa0 = add i64 1593835520, %o
  %sa = add i64 %sa0, %j
  %sp = inttoptr i64 %sa to ptr
  %c = load i8, ptr %sp
  %da = add i64 %buf, %j
  %dp = inttoptr i64 %da to ptr
  store i8 %c, ptr %dp
  %j1 = add i64 %j, 1
  br label %loop
done:
  ret i64 %len
bad:
  ret i64 -5
}

; ------------------------------------------------------------ the clock

; Call 11: the virtual counter, in seconds and then nanoseconds, so that the
; product cannot overflow. aarch64's process host reads the counter itself,
; but every kernel answers the call (spec section 10.3).
define internal i64 @sys_clock() {
  %cnt = call i64 asm sideeffect "isb\0Amrs $0, cntvct_el0", "=r"()
  %frq = call i64 @k_frq()
  %sec = udiv i64 %cnt, %frq
  %rem = urem i64 %cnt, %frq
  %remns = mul i64 %rem, 1000000000
  %ns = udiv i64 %remns, %frq
  %sns = mul i64 %sec, 1000000000
  %t = add i64 %sns, %ns
  ret i64 %t
}

; ------------------------------------------------------------ regions

; The board's devices, as runtime/board/virt-aarch64.ll gives them, spec section
; 10.3's table: a base and a length each. Not the GIC, which this kernel
; drives itself.
@devices = private constant [14 x i64] [
  i64 150994944, i64 4096,        ; 0x09000000, the PL011
  i64 151060480, i64 4096,        ; 0x09010000, the PL031
  i64 151126016, i64 24,          ; 0x09020000, firmware configuration
  i64 151191552, i64 4096,        ; 0x09030000, the PL061
  i64 167772160, i64 16384,       ; 0x0A000000, 32 virtio-mmio transports
  i64 268435456, i64 788463616,   ; 0x10000000, the PCIe 32-bit MMIO window
  i64 275146342400, i64 268435456 ] ; 0x4010000000, the PCIe ECAM

; Whether [base, base + len) lies wholly within one device. The process is
; not trusted to have checked base and len, so they are checked here.
define internal i1 @is_device(i64 %base, i64 %len) {
entry:
  %short = icmp slt i64 %len, 1
  %neg = icmp slt i64 %base, 0
  %bad = or i1 %short, %neg
  br i1 %bad, label %no, label %scan
scan:
  %end = add i64 %base, %len
  br label %loop
loop:
  %j = phi i64 [ 0, %scan ], [ %j1, %next ]
  %more = icmp ult i64 %j, 7
  br i1 %more, label %look, label %no
look:
  %k = mul i64 %j, 2
  %bp = getelementptr [14 x i64], ptr @devices, i64 0, i64 %k
  %db = load i64, ptr %bp
  %k1 = add i64 %k, 1
  %lp = getelementptr [14 x i64], ptr @devices, i64 0, i64 %k1
  %dl = load i64, ptr %lp
  %de = add i64 %db, %dl
  %from = icmp uge i64 %base, %db
  %to = icmp ule i64 %end, %de
  %within = and i1 %from, %to
  br i1 %within, label %yes, label %next
next:
  %j1 = add i64 %j, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; Maps the pages holding [base, base + len) at the next free pages of slot
; i's region window, 0xE8000000 up, as Device-nGnRnE, readable and writable
; at EL0 and never executable, and returns where base is mapped: -3 if it
; is no device, -5 if the window's 512 pages are used up.
define internal i64 @sys_region(i64 %i, i64 %base, i64 %len) {
entry:
  %dev = call i1 @is_device(i64 %base, i64 %len)
  br i1 %dev, label %room, label %none
none:
  ret i64 -3
room:
  %first = and i64 %base, -4096
  %end = add i64 %base, %len
  %last0 = sub i64 %end, 1
  %last = and i64 %last0, -4096
  %span = sub i64 %last, %first
  %n0 = lshr i64 %span, 12
  %n = add i64 %n0, 1
  %wp = call ptr @slot_word(ptr @pages, i64 %i)
  %w = load i64, ptr %wp
  %w1 = add i64 %w, %n
  %full = icmp ugt i64 %w1, 512
  br i1 %full, label %nomore, label %loop
nomore:
  ret i64 -5
loop:
  %k = phi i64 [ 0, %room ], [ %k1, %body ]
  %more = icmp ult i64 %k, %n
  br i1 %more, label %body, label %done
body:
  %off = shl i64 %k, 12
  %pa = add i64 %first, %off
  %d = or i64 %pa, 27021597764226115                        ; user device page
  %idx = add i64 %w, %k
  %ep = getelementptr [3 x [512 x i64]], ptr @l3, i64 0, i64 %i, i64 %idx
  store i64 %d, ptr %ep
  %k1 = add i64 %k, 1
  br label %loop
done:
  store i64 %w1, ptr %wp
  call void @k_sync()
  %wo = shl i64 %w, 12
  %va0 = add i64 3892314112, %wo
  %po = and i64 %base, 4095
  %va = add i64 %va0, %po
  ret i64 %va
}

; ------------------------------------------------------------ system calls

; Answers slot i's system call, its number in x8, spec section 10.3's.
; Returns 0 to resume the process, 1 when it has ended.
define internal i64 @syscall(i64 %i) {
entry:
  %p8 = call ptr @reg(i64 %i, i64 8)
  %nr = load i64, ptr %p8
  %p0 = call ptr @reg(i64 %i, i64 0)
  %a = load i64, ptr %p0
  %p1 = call ptr @reg(i64 %i, i64 1)
  %b = load i64, ptr %p1
  %p2 = call ptr @reg(i64 %i, i64 2)
  %c = load i64, ptr %p2
  %p3 = call ptr @reg(i64 %i, i64 3)
  %d = load i64, ptr %p3
  switch i64 %nr, label %unknown [ i64 1, label %read
                                   i64 2, label %write
                                   i64 3, label %exit
                                   i64 4, label %open
                                   i64 5, label %close
                                   i64 6, label %rename
                                   i64 7, label %remove
                                   i64 8, label %arg_count
                                   i64 9, label %arg
                                   i64 10, label %region
                                   i64 11, label %clock ]
read:
  %r1 = call i64 @sys_read(i64 %i, i64 %a, i64 %b, i64 %c)
  br label %answer
write:
  %r2 = call i64 @sys_write(i64 %i, i64 %a, i64 %b, i64 %c)
  br label %answer
exit:
  %st = and i64 %a, 255
  call void @end_proc(i64 %i, i64 %st, i64 0)
  ret i64 1
open:
  %r4 = call i64 @sys_open(i64 %i, i64 %a, i64 %b, i64 %c)
  br label %answer
close:
  br label %answer
rename:
  %r6 = call i64 @sys_no_file(i64 %i, i64 %a, i64 %b, i64 %c, i64 %d)
  br label %answer
remove:
  %r7 = call i64 @sys_no_file(i64 %i, i64 %a, i64 %b, i64 0, i64 0)
  br label %answer
arg_count:
  %r8 = call i64 @sys_arg_count(i64 %i)
  br label %answer
arg:
  %r9 = call i64 @sys_arg(i64 %i, i64 %a, i64 %b, i64 %c)
  br label %answer
region:
  %r10 = call i64 @sys_region(i64 %i, i64 %a, i64 %b)
  br label %answer
clock:
  %r11 = call i64 @sys_clock()
  br label %answer
unknown:
  br label %answer
answer:
  %r = phi i64 [ %r1, %read ], [ %r2, %write ], [ %r4, %open ],
               [ -5, %close ], [ %r6, %rename ], [ %r7, %remove ],
               [ %r8, %arg_count ], [ %r9, %arg ], [ %r10, %region ],
               [ %r11, %clock ], [ -5, %unknown ]
  store i64 %r, ptr %p0
  ret i64 0
}

; ------------------------------------------------------------ the loop

; The interrupt that ended a process's run: acknowledged, and if it is the
; timer's, the timer is stopped until the next slice.
define internal void @irq() {
entry:
  %iar = call i32 @mmio_r32(i64 134283276)                  ; GICC_IAR
  %id = and i32 %iar, 1023
  %spurious = icmp eq i32 %id, 1023
  br i1 %spurious, label %done, label %ack
ack:
  %timer = icmp eq i32 %id, 27
  br i1 %timer, label %tick, label %eoi
tick:
  call void @timer_off()
  br label %eoi
eoi:
  call void @mmio_w32(i64 134283280, i32 %iar)              ; GICC_EOIR
  br label %done
done:
  ret void
}

; The next runnable slot after cur, or -1.
define internal i64 @pick(i64 %cur) {
entry:
  br label %loop
loop:
  %k = phi i64 [ 1, %entry ], [ %k1, %next ]
  %s0 = add i64 %cur, %k
  %s = urem i64 %s0, 3
  %sp = call ptr @slot_word(ptr @state, i64 %s)
  %st = load i64, ptr %sp
  %run = icmp eq i64 %st, 1
  br i1 %run, label %found, label %next
next:
  %k1 = add i64 %k, 1
  %more = icmp ule i64 %k1, 3
  br i1 %more, label %loop, label %none
found:
  ret i64 %s
none:
  ret i64 -1
}

define void @k_main() noreturn {
entry:
  call void @gic_init()
  br label %scan
scan:
  %i = phi i64 [ 0, %entry ], [ %i1, %scanned ]
  %pa = call i64 @image_pa(i64 %i)
  %pp = inttoptr i64 %pa to ptr
  %w = load volatile i64, ptr %pp
  %there = icmp ne i64 %w, 0
  br i1 %there, label %make, label %scanned
make:
  call void @make_proc(i64 %i)
  br label %scanned
scanned:
  %i1 = add i64 %i, 1
  %more = icmp ult i64 %i1, 3
  br i1 %more, label %scan, label %up
up:
  %frq = call i64 @k_frq()
  %slice = udiv i64 %frq, 100                               ; 10 ms
  br label %next

; cur is the slot that ran last; the next runnable one after it runs now.
next:
  %cur = phi i64 [ 0, %up ], [ %s, %moveon ]
  %s = call i64 @pick(i64 %cur)
  %idle = icmp slt i64 %s, 0
  br i1 %idle, label %finish, label %start

; A slice starts only when the kernel moves to a process, so one that
; makes system calls cannot keep its slice from ending.
start:
  call void @timer_arm(i64 %slice)
  br label %run
run:
  %c = call ptr @ctx_of(i64 %s)
  %r = call i64 @k_user_run(ptr %c)
  %isirq = icmp eq i64 %r, -1
  br i1 %isirq, label %interrupt, label %sync
interrupt:
  call void @irq()
  br label %moveon
sync:
  %ec0 = lshr i64 %r, 26
  %ec = and i64 %ec0, 63
  %svc = icmp eq i64 %ec, 21
  br i1 %svc, label %call, label %notsvc
call:
  %ended = call i64 @syscall(i64 %s)
  %done = icmp ne i64 %ended, 0
  br i1 %done, label %moveon, label %run
notsvc:
  %dabt = icmp eq i64 %ec, 36
  %iabt = icmp eq i64 %ec, 32
  %abt = or i1 %dabt, %iabt
  br i1 %abt, label %abort, label %killit
abort:
  %dfsc = and i64 %r, 60                                    ; 0b1111xx
  %trans = icmp eq i64 %dfsc, 4                             ; translation fault
  br i1 %trans, label %demand, label %killit
demand:
  %far = call i64 @k_far()
  %ok = call i1 @map_block(i64 %s, i64 %far)
  br i1 %ok, label %run, label %why
why:
  %lo = icmp ult i64 %far, 3225419776
  %hi = icmp uge i64 %far, 3892314112
  %outside = or i1 %lo, %hi
  br i1 %outside, label %killit, label %oom
oom:
  call void @kill_oom(i64 %s)
  br label %moveon
killit:
  call void @kill(i64 %s, i64 %r)
  br label %moveon
moveon:
  %s0p = call ptr @slot_word(ptr @state, i64 0)
  %s0 = load i64, ptr %s0p
  %main_done = icmp eq i64 %s0, 2
  br i1 %main_done, label %finish, label %next
finish:
  call void @timer_off()
  %stp = call ptr @slot_word(ptr @status, i64 0)
  %st = load i64, ptr %stp
  call void @k_exit(i64 %st)
  unreachable
}

attributes #0 = { "no-builtins" }
