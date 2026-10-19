; kernel.ll -- a kernel, hand-written in IR, for QEMU's riscv64 virt board,
; that runs L0 programs built with tools/l0 build --target proc --arch
; riscv64 as processes in U-mode, each in an address space of its own, and
; answers the system calls spec section 10.3 fixes for them. It is the
; harness tools/test.sh --virt and tools/bootstrap.sh --virt test
; runtime/bare/proc.ll and runtime/arch/riscv64/proc.ll against, as
; tests/backend holds hand-written IR, and the riscv64 counterpart of
; ../aarch64/kernel.ll, shaped as that one is: one loop (k_main) that picks
; a process, returns to it with k_user_run, and handles the trap it comes
; back with, with interrupts masked throughout. OpenSBI, QEMU's firmware,
; enters it in S-mode.
;
; Physical memory, with QEMU's -m 1G:
;   0x80200000  this image, its page tables and contexts in bss
;   0x8FF00000  the kernel's stack, 1 MB, growing down
;   0x8FFFFFF8  standard input's length, then its bytes at 0x90000000
;   0x98000000  process images, 4 MB apart, put there by QEMU's loader as
;               their files: slot 0 at 0x98000000, 1 at 0x98400000, 2 at
;               0x98800000. A slot is a process when its first word is not
;               0. Its ELF's segments are moved into place in its slot,
;               and the rest zeroed, by ../elf.ll.
;   0x9EFFFFF8  the length of slot 0's arguments, then their bytes at
;               0x9F000000, each ending in a NUL; the other slots have none
;   0xA0000000  frames, 2 MB each, to 0xBC000000, given out as touched
;
; Every process sees (runtime/proc.ld, spec section 10.3):
;   0x00000000  to 0xBFFFFFFF, the kernel's identity map, S-mode only
;   0xC0000000  its slot, 4 MB, mapped when it is made: its image, and
;               after it the start of its heap
;   0xC0400000  to 0xE8000000, the rest of its heap, and its stack, a 2 MB
;               megapage mapped the first time it is touched, by a fault or
;               a system call
;   0xE8000000  to 0xE8200000, its regions: 4 KB pages of device memory,
;               mapped in order by the region system call
; Its pages are not global, and are tagged with its ASID, slot + 1, so
; switching is a write of satp and no flush; a page made valid is flushed,
; since a hart may cache that it was not.
;
; System calls (ecall, the number in a7, arguments in a0 to a3, result in
; a0), as section 10.3 numbers them, call 11 the clock among them.
; Standard output is the serial port and standard error semihosting, as on
; the board; standard input is the bytes QEMU loaded, shared. There are no
; files, and slot 0 alone has arguments.
;
; Preemption: before each return to a process the SBI's timer is set for a
; slice; its interrupt brings the process back to the kernel, which moves
; to the next. The run ends when slot 0's process ends, with its status, or
; 99 if it was killed. The kernel writes nothing of its own but a line on
; standard error for each process it kills, so a program run as slot 0
; meets the board's expectations.

target triple = "riscv64-unknown-unknown-elf"

; ------------------------------------------------------------------- boot

; The stack, the trap vector, sscratch 0 for the kernel's own traps,
; floating point on, S-mode allowed to reach user pages (SUM), user mode
; allowed to read the time, the timer's interrupt enabled in sie (it comes
; only in U-mode, since sstatus.SIE stays clear), and the boot map.
module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  la sp, __stack_top"
module asm "  csrw sscratch, zero"
module asm "  la t0, k_trap"
module asm "  csrw stvec, t0"
module asm "  li t0, 0x42000"
module asm "  csrs sstatus, t0"
module asm "  li t0, 2"
module asm "  csrs scounteren, t0"
module asm "  li t0, 32"
module asm "  csrw sie, t0"
module asm "  la t0, k_boot_pt"
module asm "  srli t0, t0, 12"
module asm "  li t1, 1"
module asm "  slli t1, t1, 63"
module asm "  or t0, t0, t1"
module asm "  csrw satp, t0"
module asm "  sfence.vma"
module asm "  call k_main"
module asm "1: j 1b"

; Every trap: sscratch is 0 while the kernel runs and the context while a
; process does. A process's trap saves its registers into the context and
; returns from k_user_run, with scause for an exception, or -1 for an
; interrupt; the kernel's own is a bug.
;
; ctx, in 8-byte words: 1 to 31 x1 to x31, 32 pc, 33 satp, 34 to 65 f0 to
; f31, 66 fcsr.
module asm ".text"
module asm ".option arch, +d"
module asm ".balign 4"
module asm "k_trap:"
module asm "  csrrw t6, sscratch, t6"
module asm "  beqz t6, 7f"
module asm "  sd x1, 8(t6)"
module asm "  sd x2, 16(t6)"
module asm "  sd x3, 24(t6)"
module asm "  sd x4, 32(t6)"
module asm "  sd x5, 40(t6)"
module asm "  sd x6, 48(t6)"
module asm "  sd x7, 56(t6)"
module asm "  sd x8, 64(t6)"
module asm "  sd x9, 72(t6)"
module asm "  sd x10, 80(t6)"
module asm "  sd x11, 88(t6)"
module asm "  sd x12, 96(t6)"
module asm "  sd x13, 104(t6)"
module asm "  sd x14, 112(t6)"
module asm "  sd x15, 120(t6)"
module asm "  sd x16, 128(t6)"
module asm "  sd x17, 136(t6)"
module asm "  sd x18, 144(t6)"
module asm "  sd x19, 152(t6)"
module asm "  sd x20, 160(t6)"
module asm "  sd x21, 168(t6)"
module asm "  sd x22, 176(t6)"
module asm "  sd x23, 184(t6)"
module asm "  sd x24, 192(t6)"
module asm "  sd x25, 200(t6)"
module asm "  sd x26, 208(t6)"
module asm "  sd x27, 216(t6)"
module asm "  sd x28, 224(t6)"
module asm "  sd x29, 232(t6)"
module asm "  sd x30, 240(t6)"
module asm "  csrr t5, sscratch"
module asm "  sd t5, 248(t6)"
module asm "  csrw sscratch, zero"
module asm "  csrr t5, sepc"
module asm "  sd t5, 256(t6)"
module asm "  fsd f0, 272(t6)"
module asm "  fsd f1, 280(t6)"
module asm "  fsd f2, 288(t6)"
module asm "  fsd f3, 296(t6)"
module asm "  fsd f4, 304(t6)"
module asm "  fsd f5, 312(t6)"
module asm "  fsd f6, 320(t6)"
module asm "  fsd f7, 328(t6)"
module asm "  fsd f8, 336(t6)"
module asm "  fsd f9, 344(t6)"
module asm "  fsd f10, 352(t6)"
module asm "  fsd f11, 360(t6)"
module asm "  fsd f12, 368(t6)"
module asm "  fsd f13, 376(t6)"
module asm "  fsd f14, 384(t6)"
module asm "  fsd f15, 392(t6)"
module asm "  fsd f16, 400(t6)"
module asm "  fsd f17, 408(t6)"
module asm "  fsd f18, 416(t6)"
module asm "  fsd f19, 424(t6)"
module asm "  fsd f20, 432(t6)"
module asm "  fsd f21, 440(t6)"
module asm "  fsd f22, 448(t6)"
module asm "  fsd f23, 456(t6)"
module asm "  fsd f24, 464(t6)"
module asm "  fsd f25, 472(t6)"
module asm "  fsd f26, 480(t6)"
module asm "  fsd f27, 488(t6)"
module asm "  fsd f28, 496(t6)"
module asm "  fsd f29, 504(t6)"
module asm "  fsd f30, 512(t6)"
module asm "  fsd f31, 520(t6)"
module asm "  frcsr t5"
module asm "  sd t5, 528(t6)"
module asm "  csrr t5, scause"
module asm "  mv a0, t5"
module asm "  bgez t5, 3f"
module asm "  li a0, -1"
module asm "3:"
module asm "  la t5, k_saved_sp"
module asm "  ld sp, 0(t5)"
module asm "  ld ra, 0(sp)"
module asm "  ld gp, 8(sp)"
module asm "  ld tp, 16(sp)"
module asm "  ld s0, 24(sp)"
module asm "  ld s1, 32(sp)"
module asm "  ld s2, 40(sp)"
module asm "  ld s3, 48(sp)"
module asm "  ld s4, 56(sp)"
module asm "  ld s5, 64(sp)"
module asm "  ld s6, 72(sp)"
module asm "  ld s7, 80(sp)"
module asm "  ld s8, 88(sp)"
module asm "  ld s9, 96(sp)"
module asm "  ld s10, 104(sp)"
module asm "  ld s11, 112(sp)"
module asm "  fld fs0, 120(sp)"
module asm "  fld fs1, 128(sp)"
module asm "  fld fs2, 136(sp)"
module asm "  fld fs3, 144(sp)"
module asm "  fld fs4, 152(sp)"
module asm "  fld fs5, 160(sp)"
module asm "  fld fs6, 168(sp)"
module asm "  fld fs7, 176(sp)"
module asm "  fld fs8, 184(sp)"
module asm "  fld fs9, 192(sp)"
module asm "  fld fs10, 200(sp)"
module asm "  fld fs11, 208(sp)"
module asm "  addi sp, sp, 224"
module asm "  ret"
module asm "7:"
module asm "  csrrw t6, sscratch, t6"
module asm "  csrr a0, scause"
module asm "  csrr a1, sepc"
module asm "  csrr a2, stval"
module asm "  call k_panic"
module asm "8: j 8b"

; k_user_run(ctx): saves what the kernel's caller expects kept on the
; kernel stack, records that stack, loads the process's address space and
; registers from ctx, and srets to U-mode with interrupts on there.
module asm ".global k_user_run"
module asm "k_user_run:"
module asm "  addi sp, sp, -224"
module asm "  sd ra, 0(sp)"
module asm "  sd gp, 8(sp)"
module asm "  sd tp, 16(sp)"
module asm "  sd s0, 24(sp)"
module asm "  sd s1, 32(sp)"
module asm "  sd s2, 40(sp)"
module asm "  sd s3, 48(sp)"
module asm "  sd s4, 56(sp)"
module asm "  sd s5, 64(sp)"
module asm "  sd s6, 72(sp)"
module asm "  sd s7, 80(sp)"
module asm "  sd s8, 88(sp)"
module asm "  sd s9, 96(sp)"
module asm "  sd s10, 104(sp)"
module asm "  sd s11, 112(sp)"
module asm "  fsd fs0, 120(sp)"
module asm "  fsd fs1, 128(sp)"
module asm "  fsd fs2, 136(sp)"
module asm "  fsd fs3, 144(sp)"
module asm "  fsd fs4, 152(sp)"
module asm "  fsd fs5, 160(sp)"
module asm "  fsd fs6, 168(sp)"
module asm "  fsd fs7, 176(sp)"
module asm "  fsd fs8, 184(sp)"
module asm "  fsd fs9, 192(sp)"
module asm "  fsd fs10, 200(sp)"
module asm "  fsd fs11, 208(sp)"
module asm "  la t0, k_saved_sp"
module asm "  sd sp, 0(t0)"
module asm "  ld t0, 264(a0)"
module asm "  csrw satp, t0"
module asm "  ld t0, 256(a0)"
module asm "  csrw sepc, t0"
module asm "  li t0, 0x100"
module asm "  csrc sstatus, t0"
module asm "  li t0, 0x20"
module asm "  csrs sstatus, t0"
module asm "  ld t0, 528(a0)"
module asm "  fscsr t0"
module asm "  fld f0, 272(a0)"
module asm "  fld f1, 280(a0)"
module asm "  fld f2, 288(a0)"
module asm "  fld f3, 296(a0)"
module asm "  fld f4, 304(a0)"
module asm "  fld f5, 312(a0)"
module asm "  fld f6, 320(a0)"
module asm "  fld f7, 328(a0)"
module asm "  fld f8, 336(a0)"
module asm "  fld f9, 344(a0)"
module asm "  fld f10, 352(a0)"
module asm "  fld f11, 360(a0)"
module asm "  fld f12, 368(a0)"
module asm "  fld f13, 376(a0)"
module asm "  fld f14, 384(a0)"
module asm "  fld f15, 392(a0)"
module asm "  fld f16, 400(a0)"
module asm "  fld f17, 408(a0)"
module asm "  fld f18, 416(a0)"
module asm "  fld f19, 424(a0)"
module asm "  fld f20, 432(a0)"
module asm "  fld f21, 440(a0)"
module asm "  fld f22, 448(a0)"
module asm "  fld f23, 456(a0)"
module asm "  fld f24, 464(a0)"
module asm "  fld f25, 472(a0)"
module asm "  fld f26, 480(a0)"
module asm "  fld f27, 488(a0)"
module asm "  fld f28, 496(a0)"
module asm "  fld f29, 504(a0)"
module asm "  fld f30, 512(a0)"
module asm "  fld f31, 520(a0)"
module asm "  csrw sscratch, a0"
module asm "  ld x1, 8(a0)"
module asm "  ld x2, 16(a0)"
module asm "  ld x3, 24(a0)"
module asm "  ld x4, 32(a0)"
module asm "  ld x5, 40(a0)"
module asm "  ld x6, 48(a0)"
module asm "  ld x7, 56(a0)"
module asm "  ld x8, 64(a0)"
module asm "  ld x9, 72(a0)"
module asm "  ld x11, 88(a0)"
module asm "  ld x12, 96(a0)"
module asm "  ld x13, 104(a0)"
module asm "  ld x14, 112(a0)"
module asm "  ld x15, 120(a0)"
module asm "  ld x16, 128(a0)"
module asm "  ld x17, 136(a0)"
module asm "  ld x18, 144(a0)"
module asm "  ld x19, 152(a0)"
module asm "  ld x20, 160(a0)"
module asm "  ld x21, 168(a0)"
module asm "  ld x22, 176(a0)"
module asm "  ld x23, 184(a0)"
module asm "  ld x24, 192(a0)"
module asm "  ld x25, 200(a0)"
module asm "  ld x26, 208(a0)"
module asm "  ld x27, 216(a0)"
module asm "  ld x28, 224(a0)"
module asm "  ld x29, 232(a0)"
module asm "  ld x30, 240(a0)"
module asm "  ld x31, 248(a0)"
module asm "  ld x10, 80(a0)"
module asm "  sret"

; QEMU's semihosting call on RISC-V: these three uncompressed instructions,
; on one page, the operation in a0 and its block in a1.
module asm ".balign 16"
module asm "k_semi:"
module asm ".option push"
module asm ".option norvc"
module asm "  slli zero, zero, 0x1f"
module asm "  ebreak"
module asm "  srai zero, zero, 7"
module asm ".option pop"
module asm "  ret"

@k_saved_sp = global i64 0

; The kernel's own map, as runtime/board/virt-riscv64.ll's: devices, then RAM.
@k_boot_pt = global <{ i64, i64, i64, [509 x i64] }> <{ i64 231, i64 0, i64 536871151, [509 x i64] zeroinitializer }>, align 4096

@root = global [3 x [512 x i64]] zeroinitializer, align 4096
@l1 = global [3 x [512 x i64]] zeroinitializer, align 4096
@l0 = global [3 x [512 x i64]] zeroinitializer, align 4096
@ctx = global [3 x [68 x i64]] zeroinitializer, align 16
@state = global [3 x i64] zeroinitializer       ; 0 none, 1 runnable, 2 ended
@status = global [3 x i64] zeroinitializer
@killed = global [3 x i64] zeroinitializer
@pages = global [3 x i64] zeroinitializer       ; region pages mapped
@next_frame = global i64 2684354560              ; 0xA0000000
@in_pos = global i64 0

@__stack_top = external global i8

declare i64 @k_user_run(ptr)
declare i64 @k_semi(i64, ptr)

; ------------------------------------------------------- the machine, small

; A page made valid, or a table changed, seen by every walk after.
define internal void @k_sync() {
  call void asm sideeffect "sfence.vma", "~{memory}"()
  ret void
}

; The time CSR, at the board's 10,000,000 counts a second.
define internal i64 @k_time() {
  %t = call i64 asm sideeffect "rdtime $0", "=r"()
  ret i64 %t
}

define internal i64 @k_frq() {
  ret i64 10000000
}

; SBI's TIME extension: the supervisor timer's interrupt at time t.
define internal void @set_timer(i64 %t) {
  %r = call i64 asm sideeffect "ecall", "={x10},{x10},{x16},{x17},~{x11},~{memory}"(i64 %t, i64 0, i64 1414090053)
  ret void
}

define internal void @timer_arm(i64 %ticks) {
  %now = call i64 @k_time()
  %t = add i64 %now, %ticks
  call void @set_timer(i64 %t)
  ret void
}

define internal void @timer_off() {
  call void @set_timer(i64 -1)
  ret void
}

; ------------------------------------------------------------ semihosting

define internal i64 @semi(i64 %op, ptr %blk) {
  %r = call i64 @k_semi(i64 %op, ptr %blk)
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
@m_cause = private constant [11 x i8] c" scause = \00"
@m_epc = private constant [9 x i8] c" sepc = \00"
@m_tval = private constant [10 x i8] c" stval = \00"
@m_nl = private constant [2 x i8] c"\0A\00"

define void @k_panic(i64 %cause, i64 %epc, i64 %tval) noreturn {
  call void @say(ptr @m_panic)
  call void @say(ptr @m_cause)
  call void @say_hex(i64 %cause)
  call void @say(ptr @m_epc)
  call void @say_hex(i64 %epc)
  call void @say(ptr @m_tval)
  call void @say_hex(i64 %tval)
  call void @say(ptr @m_nl)
  call void @k_exit(i64 99)
  unreachable
}

; The 16550 at 0x10000000: its line status register, at 5, has bit 5 set
; when the transmit holding register, at 0, is empty.
define internal void @uart_put(i8 %c) {
entry:
  br label %wait
wait:
  %lsr = load volatile i8, ptr inttoptr (i64 268435461 to ptr)
  %e = and i8 %lsr, 32
  %full = icmp eq i8 %e, 0
  br i1 %full, label %wait, label %send
send:
  store volatile i8 %c, ptr inttoptr (i64 268435456 to ptr)
  ret void
}

; ------------------------------------------------------------ the tables

define internal ptr @slot_word(ptr %table, i64 %i) {
  %p = getelementptr [3 x i64], ptr %table, i64 0, i64 %i
  ret ptr %p
}

define internal ptr @ctx_of(i64 %i) {
  %p = getelementptr [3 x [68 x i64]], ptr @ctx, i64 0, i64 %i, i64 0
  ret ptr %p
}

define internal ptr @reg(i64 %i, i64 %r) {
  %p = getelementptr [3 x [68 x i64]], ptr @ctx, i64 0, i64 %i, i64 %r
  ret ptr %p
}

define internal i64 @image_pa(i64 %i) {
  %o = mul i64 %i, 4194304
  %a = add i64 2550136832, %o                               ; 0x98000000
  ret i64 %a
}

; Sv39's descriptor of the page or table at pa, with these bits.
define internal i64 @pte(i64 %pa, i64 %bits) {
  %ppn = lshr i64 %pa, 12
  %f = shl i64 %ppn, 10
  %d = or i64 %f, %bits
  ret i64 %d
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
  %out = icmp uge i64 %f, 3154116608                        ; 0xBC000000
  br i1 %out, label %none, label %take
none:
  ret i64 0
take:
  %f1 = add i64 %f, 2097152
  store i64 %f1, ptr @next_frame
  call void @zero_frame(i64 %f)
  ret i64 %f
}

; Whether the 2 MB megapage holding va, in slot i's heap and stack, is
; mapped already.
define internal i1 @block_mapped(i64 %i, i64 %va) {
entry:
  %lo = icmp ult i64 %va, 3225419776
  %hi = icmp uge i64 %va, 3892314112
  %out = or i1 %lo, %hi
  br i1 %out, label %no, label %look
look:
  %off = sub i64 %va, 3221225472
  %idx = lshr i64 %off, 21
  %ep = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 %idx
  %e = load i64, ptr %ep
  %have = icmp ne i64 %e, 0
  ret i1 %have
no:
  ret i1 false
}

; Maps the 2 MB megapage holding va, in slot i's heap and stack, if it is
; not mapped yet. False when va is not in them, or no frame is left.
define internal i1 @map_block(i64 %i, i64 %va) {
entry:
  %lo = icmp ult i64 %va, 3225419776
  %hi = icmp uge i64 %va, 3892314112
  %out = or i1 %lo, %hi
  br i1 %out, label %no, label %look
look:
  %off = sub i64 %va, 3221225472
  %idx = lshr i64 %off, 21
  %ep = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 %idx
  %e = load i64, ptr %ep
  %have = icmp ne i64 %e, 0
  br i1 %have, label %yes, label %new
new:
  %f = call i64 @alloc_frame()
  %none = icmp eq i64 %f, 0
  br i1 %none, label %no, label %put
put:
  %d = call i64 @pte(i64 %f, i64 215)                       ; V R W U A D
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
; buffer. An empty range touches nothing, and is always in. va is bounded
; before va + n is formed, so the sum cannot wrap.
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
  %e0 = getelementptr [3 x [512 x i64]], ptr @root, i64 0, i64 %i, i64 0
  store i64 231, ptr %e0                                    ; devices
  %e2 = getelementptr [3 x [512 x i64]], ptr @root, i64 0, i64 %i, i64 2
  store i64 536871151, ptr %e2                              ; RAM, S-mode only
  %t = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 0
  %tpa = ptrtoint ptr %t to i64
  %td = call i64 @pte(i64 %tpa, i64 1)
  %e3 = getelementptr [3 x [512 x i64]], ptr @root, i64 0, i64 %i, i64 3
  store i64 %td, ptr %e3
  %img = call i64 @image_pa(i64 %i)
  %pc0 = call i64 @elf_load(i64 %img, i64 243)              ; EM_RISCV
  %c0 = call i64 @pte(i64 %img, i64 223)                    ; V R W X U A D
  store i64 %c0, ptr %t
  %img1 = add i64 %img, 2097152
  %c1 = call i64 @pte(i64 %img1, i64 223)
  %t1 = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 1
  store i64 %c1, ptr %t1
  ; 0xE8000000, level 1 entry 320: the table of this process's regions
  %r = getelementptr [3 x [512 x i64]], ptr @l0, i64 0, i64 %i, i64 0
  %rpa = ptrtoint ptr %r to i64
  %rd = call i64 @pte(i64 %rpa, i64 1)
  %t320 = getelementptr [3 x [512 x i64]], ptr @l1, i64 0, i64 %i, i64 320
  store i64 %rd, ptr %t320
  %rootpa = ptrtoint ptr %e0 to i64
  %ppn = lshr i64 %rootpa, 12
  %asid = add i64 %i, 1
  %tag = shl i64 %asid, 44
  %s0 = or i64 %ppn, %tag
  %satp = or i64 %s0, -9223372036854775808                  ; Sv39
  %r33 = call ptr @reg(i64 %i, i64 33)
  store i64 %satp, ptr %r33
  %r2 = call ptr @reg(i64 %i, i64 2)
  store i64 3892314112, ptr %r2                             ; sp, 0xE8000000
  %r32 = call ptr @reg(i64 %i, i64 32)
  store i64 %pc0, ptr %r32                                  ; pc, the entry
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

define internal void @kill(i64 %i, i64 %cause) {
  %tval = call i64 asm sideeffect "csrr $0, stval", "=r"()
  %ep = call ptr @reg(i64 %i, i64 32)
  %pc = load i64, ptr %ep
  call void @say(ptr @m_proc)
  call void @say_dec(i64 %i)
  call void @say(ptr @m_killed)
  call void @say(ptr @m_fault)
  call void @say(ptr @m_cause)
  call void @say_hex(i64 %cause)
  call void @say(ptr @m_epc)
  call void @say_hex(i64 %pc)
  call void @say(ptr @m_tval)
  call void @say_hex(i64 %tval)
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
  %len = load i64, ptr inttoptr (i64 2415919096 to ptr)     ; 0x8FFFFFF8
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
  %sa0 = add i64 2415919104, %pos                           ; 0x90000000
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

; Slot 0's arguments are the bytes at 0x9F000000, each ending in a NUL,
; and as many as the word below them says.
define internal i64 @args_len() {
  %n = load i64, ptr inttoptr (i64 2667577336 to ptr)       ; 0x9EFFFFF8
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
  %a = add i64 2667577344, %j                               ; 0x9F000000
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
  %sa0 = add i64 2667577344, %o
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

; Call 11: the time CSR, in seconds and then nanoseconds, so that the
; product cannot overflow, which a process cannot read alone, since it does
; not know the board's timebase.
define internal i64 @sys_clock() {
  %cnt = call i64 @k_time()
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

; The board's devices, as runtime/board/virt-riscv64.ll gives them, spec
; section 10.3's table: a base and a length each. Not the PLIC.
@devices = private constant [8 x i64] [
  i64 268435456, i64 256,         ; 0x10000000, the 16550
  i64 1052672, i64 4096,          ; 0x00101000, the goldfish RTC
  i64 269484032, i64 24,          ; 0x10100000, firmware configuration
  i64 268439552, i64 32768 ]      ; 0x10001000, 8 virtio-mmio transports

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
  %more = icmp ult i64 %j, 4
  br i1 %more, label %look, label %no
look:
  %k = mul i64 %j, 2
  %bp = getelementptr [8 x i64], ptr @devices, i64 0, i64 %k
  %db = load i64, ptr %bp
  %k1 = add i64 %k, 1
  %lp = getelementptr [8 x i64], ptr @devices, i64 0, i64 %k1
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
; i's region window, 0xE8000000 up, readable and writable in U-mode and
; never executable, and returns where base is mapped: -3 if it is no
; device, -5 if the window's 512 pages are used up.
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
  %d = call i64 @pte(i64 %pa, i64 215)                      ; V R W U A D
  %idx = add i64 %w, %k
  %ep = getelementptr [3 x [512 x i64]], ptr @l0, i64 0, i64 %i, i64 %idx
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

; Answers slot i's system call, its number in a7, word 17, its arguments in
; a0 to a3, words 10 to 13, spec section 10.3's. Returns 0 to resume the
; process, 1 when it has ended.
define internal i64 @syscall(i64 %i) {
entry:
  %p17 = call ptr @reg(i64 %i, i64 17)
  %nr = load i64, ptr %p17
  %p10 = call ptr @reg(i64 %i, i64 10)
  %a = load i64, ptr %p10
  %p11 = call ptr @reg(i64 %i, i64 11)
  %b = load i64, ptr %p11
  %p12 = call ptr @reg(i64 %i, i64 12)
  %c = load i64, ptr %p12
  %p13 = call ptr @reg(i64 %i, i64 13)
  %d = load i64, ptr %p13
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
  store i64 %r, ptr %p10
  ret i64 0
}

; ------------------------------------------------------------ the loop

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
  call void @timer_off()
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
  call void @timer_off()
  br label %moveon
sync:
  %ecall = icmp eq i64 %r, 8
  br i1 %ecall, label %call, label %notcall
call:
  %pcp = call ptr @reg(i64 %s, i64 32)
  %pc = load i64, ptr %pcp
  %pc4 = add i64 %pc, 4
  store i64 %pc4, ptr %pcp
  %ended = call i64 @syscall(i64 %s)
  %done = icmp ne i64 %ended, 0
  br i1 %done, label %moveon, label %run
notcall:
  %f12 = icmp eq i64 %r, 12
  %f13 = icmp eq i64 %r, 13
  %f15 = icmp eq i64 %r, 15
  %f0 = or i1 %f12, %f13
  %pf = or i1 %f0, %f15
  br i1 %pf, label %page, label %killit
page:
  %tval = call i64 asm sideeffect "csrr $0, stval", "=r"()
  %there2 = call i1 @block_mapped(i64 %s, i64 %tval)
  br i1 %there2, label %killit, label %demand
demand:
  %ok = call i1 @map_block(i64 %s, i64 %tval)
  br i1 %ok, label %run, label %why
why:
  %lo = icmp ult i64 %tval, 3225419776
  %hi = icmp uge i64 %tval, 3892314112
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
