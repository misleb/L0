; kernel.ll -- 0074's prototype: a kernel stub, hand-written in IR, for
; QEMU's aarch64 virt board. It runs up to three processes at EL0, each in an
; address space of its own, and is shaped as an L0 kernel would be: one loop
; (k_main) that picks a process, returns to it with k_user_run, and handles
; the trap it comes back with, with interrupts masked throughout. k_user_run
; is the proposed `user_run` builtin's mechanism: it takes a context, a
; thread's registers as 102 words, and returns when the thread next traps,
; with the context updated and the reason in its result.
;
; Physical memory, with QEMU's -m 2G:
;   0x40080000  this image, its page tables and contexts in bss
;   0x4FF00000  the kernel's stack, 1 MB, growing down
;   0x4FFFFFF8  standard input's length, then its bytes at 0x50000000
;   0x58000000  process images, 4 MB apart, put there by QEMU's loader:
;               slot 0 at 0x58000000, 1 at 0x58400000, 2 at 0x58800000.
;               A slot is a process when its first word is not 0.
;   0x60000000  frames, 2 MB each, to 0xC0000000, given out as touched
;
; Every process sees (proc.ld):
;   0x00000000  to 0xBFFFFFFF, the kernel's identity map, EL1 only, never
;               executable at EL0
;   0xC0000000  its image, 4 MB, mapped when it is made
;   0xC0400000  to 0xE8000000, its heap and stack, a 2 MB block mapped the
;               first time it is touched, by a fault or a system call
; The level 2 entries are 2 MB blocks, not global, tagged with the
; process's ASID, slot + 1, so switching is a write of TTBR0 and no flush.
;
; System calls (svc #0, the number in x8, arguments in x0 to x2, result in
; x0): 1 read(stream, buf, n), 2 write(stream, buf, n), 3 exit(status).
; Standard output is the serial port and standard error semihosting, as on
; the board; standard input is the bytes QEMU loaded, shared.
;
; Preemption: before each return to a process the virtual timer is set for
; a slice; its interrupt, PPI 27 through the GICv2, brings the process back
; to the kernel, which moves to the next. The run ends when slot 0's
; process ends, with its status, after a line per process on standard
; error saying how it ended and what it cost.

target triple = "aarch64-unknown-none-elf"

; ------------------------------------------------------------------- boot

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
module asm "  ldr x0, =0x803520"
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

; The kernel's own map, as runtime/host-virt.ll's: devices, then RAM.
@k_boot_pt = global [4 x i64] [i64 1025, i64 1073743621, i64 2147485445, i64 0], align 4096

@l1 = global [3 x [512 x i64]] zeroinitializer, align 4096
@l2 = global [3 x [512 x i64]] zeroinitializer, align 4096
@ctx = global [3 x [102 x i64]] zeroinitializer, align 16
@state = global [3 x i64] zeroinitializer       ; 0 none, 1 runnable, 2 ended
@status = global [3 x i64] zeroinitializer
@killed = global [3 x i64] zeroinitializer
@preempts = global [3 x i64] zeroinitializer
@syscalls = global [3 x i64] zeroinitializer
@blocks = global [3 x i64] zeroinitializer
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

define internal void @bump(ptr %table, i64 %i) {
  %p = call ptr @slot_word(ptr %table, i64 %i)
  %v = load i64, ptr %p
  %v1 = add i64 %v, 1
  store i64 %v1, ptr %p
  ret void
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
  call void @bump(ptr @blocks, i64 %i)
  br label %yes
yes:
  ret i1 true
no:
  ret i1 false
}

; Whether [va, va + n) is in slot i's memory, mapping what is not yet; the
; check a kernel must make before it touches a process's buffer, which in
; L0 would be a copy into or out of a space handle rather than an address.
define internal i1 @user_range(i64 %i, i64 %va, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  %big = icmp ugt i64 %n, 1073741824
  %badn = or i1 %neg, %big
  %lo = icmp ult i64 %va, 3221225472
  %bad0 = or i1 %badn, %lo
  %end = add i64 %va, %n
  %hi = icmp ugt i64 %end, 3892314112
  %bad = or i1 %bad0, %hi
  br i1 %bad, label %no, label %empty
empty:
  %zero = icmp eq i64 %n, 0
  br i1 %zero, label %yes, label %first
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
  %c0 = or i64 %img, 9007199254744901                       ; user code
  store i64 %c0, ptr %t
  %img1 = add i64 %img, 2097152
  %c1 = or i64 %img1, 9007199254744901
  %t1 = getelementptr [3 x [512 x i64]], ptr @l2, i64 0, i64 %i, i64 1
  store i64 %c1, ptr %t1
  %l1p = ptrtoint ptr %e0 to i64
  %asid = add i64 %i, 1
  %tag = shl i64 %asid, 48
  %ttbr = or i64 %l1p, %tag
  %r34 = call ptr @reg(i64 %i, i64 34)
  store i64 %ttbr, ptr %r34
  %r31 = call ptr @reg(i64 %i, i64 31)
  store i64 3892314112, ptr %r31                            ; sp, 0xE8000000
  %r32 = call ptr @reg(i64 %i, i64 32)
  store i64 3221225472, ptr %r32                            ; pc, 0xC0000000
  %r33 = call ptr @reg(i64 %i, i64 33)
  store i64 0, ptr %r33                                     ; EL0t, unmasked
  %sp = call ptr @slot_word(ptr @state, i64 %i)
  store i64 1, ptr %sp
  call void @k_sync()
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
  call void @end_proc(i64 %i, i64 0, i64 1)
  ret void
}

define internal void @kill_oom(i64 %i) {
  call void @say(ptr @m_proc)
  call void @say_dec(i64 %i)
  call void @say(ptr @m_killed)
  call void @say(ptr @m_oom)
  call void @say(ptr @m_nl)
  call void @end_proc(i64 %i, i64 0, i64 1)
  ret void
}

; ------------------------------------------------------------ system calls

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

; Answers slot i's system call, its number in x8. Returns 0 to resume the
; process, 1 when it has ended.
define internal i64 @syscall(i64 %i) {
entry:
  call void @bump(ptr @syscalls, i64 %i)
  %p8 = call ptr @reg(i64 %i, i64 8)
  %nr = load i64, ptr %p8
  %p0 = call ptr @reg(i64 %i, i64 0)
  %a = load i64, ptr %p0
  %p1 = call ptr @reg(i64 %i, i64 1)
  %b = load i64, ptr %p1
  %p2 = call ptr @reg(i64 %i, i64 2)
  %c = load i64, ptr %p2
  switch i64 %nr, label %unknown [ i64 1, label %read
                                   i64 2, label %write
                                   i64 3, label %exit ]
read:
  %r1 = call i64 @sys_read(i64 %i, i64 %a, i64 %b, i64 %c)
  store i64 %r1, ptr %p0
  ret i64 0
write:
  %r2 = call i64 @sys_write(i64 %i, i64 %a, i64 %b, i64 %c)
  store i64 %r2, ptr %p0
  ret i64 0
exit:
  %st = and i64 %a, 255
  call void @end_proc(i64 %i, i64 %st, i64 0)
  ret i64 1
unknown:
  store i64 -5, ptr %p0
  ret i64 0
}

; ------------------------------------------------------------ the loop

; The interrupt that ended a process's run: acknowledged, and if it is the
; timer's, the timer is stopped until the next slice.
define internal void @irq(i64 %i) {
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
  call void @bump(ptr @preempts, i64 %i)
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

@m_start = private constant [13 x i8] c"kernel: up, \00"
@m_procs = private constant [12 x i8] c" processes\0A\00"
@m_exited = private constant [21 x i8] c" exited with status \00"
@m_was_killed = private constant [12 x i8] c" was killed\00"
@m_never = private constant [13 x i8] c" was stopped\00"
@m_cost = private constant [3 x i8] c", \00"
@m_pre = private constant [15 x i8] c" preemptions, \00"
@m_sys = private constant [17 x i8] c" system calls, \00\00"
@m_blk = private constant [25 x i8] c" heap and stack blocks\0A\00\00"

define internal void @report(i64 %i) {
entry:
  %sp = call ptr @slot_word(ptr @state, i64 %i)
  %st = load i64, ptr %sp
  %none = icmp eq i64 %st, 0
  br i1 %none, label %done, label %say
say:
  call void @say(ptr @m_proc)
  call void @say_dec(i64 %i)
  %kp = call ptr @slot_word(ptr @killed, i64 %i)
  %k = load i64, ptr %kp
  %ended = icmp eq i64 %st, 2
  br i1 %ended, label %how, label %stopped
stopped:
  call void @say(ptr @m_never)
  br label %cost
how:
  %wk = icmp ne i64 %k, 0
  br i1 %wk, label %waskilled, label %exited
waskilled:
  call void @say(ptr @m_was_killed)
  br label %cost
exited:
  call void @say(ptr @m_exited)
  %stp = call ptr @slot_word(ptr @status, i64 %i)
  %s = load i64, ptr %stp
  call void @say_dec(i64 %s)
  br label %cost
cost:
  call void @say(ptr @m_cost)
  %pp = call ptr @slot_word(ptr @preempts, i64 %i)
  %p = load i64, ptr %pp
  call void @say_dec(i64 %p)
  call void @say(ptr @m_pre)
  %yp = call ptr @slot_word(ptr @syscalls, i64 %i)
  %y = load i64, ptr %yp
  call void @say_dec(i64 %y)
  call void @say(ptr @m_sys)
  %bp = call ptr @slot_word(ptr @blocks, i64 %i)
  %b = load i64, ptr %bp
  call void @say_dec(i64 %b)
  call void @say(ptr @m_blk)
  br label %done
done:
  ret void
}

define void @k_main() noreturn {
entry:
  call void @gic_init()
  br label %scan
scan:
  %i = phi i64 [ 0, %entry ], [ %i1, %scanned ]
  %n = phi i64 [ 0, %entry ], [ %n1, %scanned ]
  %pa = call i64 @image_pa(i64 %i)
  %pp = inttoptr i64 %pa to ptr
  %w = load volatile i64, ptr %pp
  %there = icmp ne i64 %w, 0
  br i1 %there, label %make, label %scanned
make:
  call void @make_proc(i64 %i)
  br label %scanned
scanned:
  %add = zext i1 %there to i64
  %n1 = add i64 %n, %add
  %i1 = add i64 %i, 1
  %more = icmp ult i64 %i1, 3
  br i1 %more, label %scan, label %up
up:
  call void @say(ptr @m_start)
  call void @say_dec(i64 %n1)
  call void @say(ptr @m_procs)
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
  call void @irq(i64 %s)
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
  call void @report(i64 0)
  call void @report(i64 1)
  call void @report(i64 2)
  %stp = call ptr @slot_word(ptr @status, i64 0)
  %st = load i64, ptr %stp
  call void @k_exit(i64 %st)
  unreachable
}

attributes #0 = { "no-builtins" }
