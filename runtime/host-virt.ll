; host-virt.ll -- the host file for QEMU's aarch64 virt board, with no
; operating system: spec section 9.2's host without one. runtime/l0rt.ll
; calls the l0_host_ functions below, spec section 10.3, and this file boots
; the board and calls @l0_rt_run. runtime/virt.ld lays out the image, and
; runtime/freestanding.ll, linked beside it, gives the allocator over its
; heap and the mem functions.
;
; It names its machine's triple, unlike l0rt.ll and host-libc.ll, since the
; boot code is aarch64 assembly.
;
; It boots by the arm64 boot protocol (spec section 10.3): a raw image with
; the protocol's header, entered with the device tree's address in x0.
;
; Memory, with QEMU's -m 2G (RAM is 0x40000000 to 0xC0000000):
;   0x40080000  the image: code, data, bss, which the boot code zeroes
;   0x48000000  the device tree, where QEMU puts it for this protocol; the
;               image must end below it, and the arguments are copied out
;               of it before the program starts
;   0x4FFFFFF8  standard input's length, a word, written by QEMU's loader
;   0x50000000  standard input's bytes, loaded by QEMU's loader
;   0x58000000  the heap, to 0x98000000
;   0x98000000  the pool of frames and the spaces' page tables, to 0xB0000000
;   0xB0000000  the stack, 256 MB, growing down from 0xC0000000
;   0xC0000000  to 0x100000000, the user range, mapped by each space alone
;
; Standard input is the bytes QEMU loaded, since a serial line has no end
; of input; with none loaded the length word is 0 and input is empty.
; Standard output is the PL011 serial port at 0x09000000. Standard error
; and the exit status reach the host by semihosting, so the three stay
; apart on a board with one serial line. The arguments are the boot
; arguments, the device tree's /chosen/bootargs, split at runs of spaces.
; As section 9.2 says, there are no files and no environment. The clock is
; the generic timer.
; The board's devices are what a program may open as regions (spec section
; 6.12), the serial port among them, but not the interrupt controller,
; which this file drives (spec section 6.14). A program runs at EL1, with
; interrupts masked, and may run threads at EL0 in spaces of its own (spec
; section 6.13).
;
; An exception the runtime does not expect is a bug in it, and is reported
; on standard error, with the registers that say where, and stops with
; status 99.

target triple = "aarch64-unknown-none-elf"

; ------------------------------------------------------------------- boot

; The arm64 boot protocol's header (Linux's Documentation/arm64/booting): a
; branch past it, a text offset of 0x80000 from the base of RAM, the
; image's size with its bss, no flags, and the magic "ARM\x64". A loader
; that sees it enters at _start with the device tree's address in x0.
module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  b l0_virt_boot"
module asm "  .word 0"
module asm "  .quad 0x80000"
module asm "  .quad 0x7F80000"
module asm "  .quad 0"
module asm "  .quad 0, 0, 0"
module asm "  .word 0x644d5241"
module asm "  .word 0"
module asm "l0_virt_boot:"
module asm "  mov x20, x0"
module asm "  mov x0, #(3 << 20)"
module asm "  msr cpacr_el1, x0"
module asm "  isb"
module asm "  ldr x0, =__stack_top"
module asm "  mov sp, x0"
module asm "  ldr x0, =l0_virt_vectors"
module asm "  msr vbar_el1, x0"
module asm "  mov x0, #3"
module asm "  msr cntkctl_el1, x0"
module asm "  mov x0, #0xff00"
module asm "  msr mair_el1, x0"
module asm "  ldr x0, =0x803520"
module asm "  msr tcr_el1, x0"
module asm "  ldr x0, =l0_virt_pt"
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
module asm "  bl l0_virt_main"
module asm "1: b 1b"

; An exception at EL1 is the runtime's own bug. From EL0, at 0x400 (a
; synchronous exception: a system call or a fault) and 0x480 (an IRQ), it
; is a thread's trap, and ends its l0_virt_user_run.
module asm ".balign 2048"
module asm "l0_virt_vectors:"
module asm ".rept 8"
module asm ".balign 128"
module asm "  b l0_virt_trap_entry"
module asm ".endr"
module asm ".balign 128"
module asm "  b l0_virt_user_sync"
module asm ".balign 128"
module asm "  b l0_virt_user_irq"
module asm ".rept 6"
module asm ".balign 128"
module asm "  b l0_virt_trap_entry"
module asm ".endr"
module asm "l0_virt_trap_entry:"
module asm "  mrs x0, esr_el1"
module asm "  mrs x1, elr_el1"
module asm "  mrs x2, far_el1"
module asm "  bl l0_virt_trap"
module asm "2: b 2b"

; l0_virt_user_run(words, ttbr): saves what its caller expects kept (x19 to
; x30, d8 to d15) on this stack, records the stack and the context's words,
; switches to the thread's space, loads its registers from the words, and
; erets to EL0. Spec section 10.3 lays the words out, in bytes: x0 to x30
; at 0, sp 248, pc 256, pstate 264, tpidr_el0 272, the trap's kind 280, its
; syndrome 288 and address 296, q0 to q31 from 304, fpcr 816, fpsr 824.
module asm ".text"
module asm ".global l0_virt_user_run"
module asm "l0_virt_user_run:"
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
module asm "  adrp x9, l0_virt_user_sp"
module asm "  mov x10, sp"
module asm "  str x10, [x9, :lo12:l0_virt_user_sp]"
module asm "  adrp x9, l0_virt_user_ctx"
module asm "  str x0, [x9, :lo12:l0_virt_user_ctx]"
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
; exception, and l0_virt_user_run returns to its caller.
module asm "l0_virt_user_sync:"
module asm "  stp x0, x1, [sp, #-16]!"
module asm "  mov x1, #0"
module asm "  b l0_virt_user_save"
module asm "l0_virt_user_irq:"
module asm "  stp x0, x1, [sp, #-16]!"
module asm "  mov x1, #1"
module asm "l0_virt_user_save:"
module asm "  adrp x0, l0_virt_user_ctx"
module asm "  ldr x0, [x0, :lo12:l0_virt_user_ctx]"
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
module asm "  adrp x9, l0_virt_user_sp"
module asm "  ldr x9, [x9, :lo12:l0_virt_user_sp]"
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

; The boot code enables floating point and SIMD, which LLVM may use for
; copies, and the MMU, with this identity map in 1 GB blocks at level 1
; (TCR T0SZ 32, 4 KB granule). Block 0 holds the devices, MAIR attribute 0,
; Device-nGnRnE; blocks 1 and 2 are the RAM, attribute 1, normal
; write-back, inner shareable. With the MMU off every access would be to
; device memory, where an unaligned one faults. Block 3, the 4th gigabyte,
; is the user range, which only a space maps. The boot code also lets EL0
; read the virtual counter, and sets the SCTLR bits that let it read
; CTR_EL0 and zero by cache line, which LLVM may emit for a thread.
@l0_virt_pt = global [4 x i64] [i64 1025, i64 1073743621, i64 2147485445, i64 0], align 4096

@__stack_top = external global i8
@__stack_bottom = external global i8

; Defined by runtime/l0rt.ll. Spec section 10.3.
declare i64 @l0_rt_run(i64)

; Defined by runtime/freestanding.ll.
declare ptr @memcpy(ptr, ptr, i64)

; Called by _start on the boot stack, with the device tree's address. The
; arguments are copied out of it before anything else, since the tree is
; wherever the firmware put it. l0_rt_run's frame is a little below the
; top, so the size it is given leaves 64 KB for what lies above it.
define void @l0_virt_main(i64 %dtb) noreturn {
entry:
  call void @boot_args(i64 %dtb)
  call void @gic_init()
  %top = ptrtoint ptr @__stack_top to i64
  %bottom = ptrtoint ptr @__stack_bottom to i64
  %all = sub i64 %top, %bottom
  %size = sub i64 %all, 65536
  %st = call i64 @l0_rt_run(i64 %size)
  call void @l0_host_exit(i64 %st)
  unreachable
}

@m_trap = private constant [29 x i8] c"l0: machine exception: esr = "
@m_elr = private constant [8 x i8] c", elr = "
@m_far = private constant [8 x i8] c", far = "
@m_nl = private constant [1 x i8] c"\0A"
@hexd = private constant [16 x i8] c"0123456789abcdef"

define internal void @put_hex(i64 %v) {
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
  %w = call i64 @l0_host_write(i64 2, ptr %buf, i64 18)
  ret void
}

define void @l0_virt_trap(i64 %esr, i64 %elr, i64 %far) noreturn {
entry:
  %a = call i64 @l0_host_write(i64 2, ptr @m_trap, i64 29)
  call void @put_hex(i64 %esr)
  %b = call i64 @l0_host_write(i64 2, ptr @m_elr, i64 8)
  call void @put_hex(i64 %elr)
  %c = call i64 @l0_host_write(i64 2, ptr @m_far, i64 8)
  call void @put_hex(i64 %far)
  %d = call i64 @l0_host_write(i64 2, ptr @m_nl, i64 1)
  call void @l0_host_exit(i64 99)
  unreachable
}

; ------------------------------------------------------------ semihosting

define internal i64 @semi(i64 %op, ptr %blk) {
entry:
  %r = call i64 asm sideeffect "hlt #0xf000", "={x0},{x0},{x1},~{memory}"(i64 %op, ptr %blk)
  ret i64 %r
}

; SYS_EXIT with ADP_Stopped_ApplicationExit, whose subcode, the status, QEMU
; makes its own exit status.
define void @l0_host_exit(i64 %status) noreturn {
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

; ":tt" opened in mode 8, "a", is the host's standard error.
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

; ----------------------------------------------------------------- streams

; Waits while the PL011's transmit FIFO is full, flag register bit 5.
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

@in_pos = internal global i64 0

define i64 @l0_host_read(i64 %s, ptr %buf, i64 %n) {
entry:
  %is0 = icmp eq i64 %s, 0
  br i1 %is0, label %input, label %bad
bad:
  ret i64 -5
input:
  %len = load i64, ptr inttoptr (i64 1342177272 to ptr)
  %pos = load i64, ptr @in_pos
  %left = sub i64 %len, %pos
  %less = icmp ult i64 %left, %n
  %k = select i1 %less, i64 %left, i64 %n
  %src = getelementptr i8, ptr inttoptr (i64 1342177280 to ptr), i64 %pos
  %x = call ptr @memcpy(ptr %buf, ptr %src, i64 %k)
  %np = add i64 %pos, %k
  store i64 %np, ptr @in_pos
  ret i64 %k
}

define i64 @l0_host_write(i64 %s, ptr %buf, i64 %n) {
entry:
  %is1 = icmp eq i64 %s, 1
  br i1 %is1, label %uart, label %not1
not1:
  %is2 = icmp eq i64 %s, 2
  br i1 %is2, label %err, label %bad
bad:
  ret i64 -5
uart:
  br label %loop
loop:
  %i = phi i64 [ 0, %uart ], [ %i1, %body ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr i8, ptr %buf, i64 %i
  %c = load i8, ptr %p
  call void @uart_put(i8 %c)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %n
err:
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
  %none = icmp sle i64 %wrote, 0
  %r = select i1 %none, i64 -5, i64 %wrote
  ret i64 %r
}

; No stream but the standard three is ever open, and those are not closed.
define i64 @l0_host_close(i64 %s) {
entry:
  ret i64 -5
}

; ------------------------------------------------------------------- files

; Section 9.2: an empty file system, not even a directory, in which nothing
; can be made.
define i64 @l0_host_open(ptr %path, i64 %mode) {
entry:
  %rd = icmp eq i64 %mode, 1
  %r = select i1 %rd, i64 -3, i64 -9
  ret i64 %r
}

define i64 @l0_host_rename(ptr %from, ptr %to) {
entry:
  ret i64 -3
}

define i64 @l0_host_remove(ptr %path) {
entry:
  ret i64 -3
}

; ------------------------------------------- the clock, arguments, settings

; The generic timer's virtual count, at cntfrq_el0 counts a second, in
; seconds and then nanoseconds, so that the product cannot overflow.
define i64 @l0_host_clock_ns() {
entry:
  %cnt = call i64 asm sideeffect "isb\0Amrs $0, cntvct_el0", "=r"()
  %frq = call i64 asm "mrs $0, cntfrq_el0", "=r"()
  %none = icmp eq i64 %frq, 0
  br i1 %none, label %no, label %yes
no:
  ret i64 -5
yes:
  %sec = udiv i64 %cnt, %frq
  %rem = urem i64 %cnt, %frq
  %remns = mul i64 %rem, 1000000000
  %ns = udiv i64 %remns, %frq
  %sns = mul i64 %sec, 1000000000
  %t = add i64 %sns, %ns
  ret i64 %t
}

; ---------------------------------------------------------- the arguments
;
; Spec section 10.3: the boot arguments, the bootargs property of the
; device tree's /chosen node, split at runs of spaces. The device tree is
; read as the Devicetree Specification lays it out, big-endian: a header
; whose words 1 to 3 are its total size and the offsets of its structure
; and strings blocks, then tokens, 1 a node's beginning and its name, 2 its
; end, 3 a property with its length and the offset of its name, 4 nothing,
; 9 the end. The bytes are copied into args_buf, the spaces become NULs,
; and arg_at holds where each argument starts.

@args_buf = internal global [65536 x i8] zeroinitializer
@arg_at = internal global [4096 x i64] zeroinitializer
@arg_n = internal global i64 0
@s_chosen = private constant [7 x i8] c"chosen\00"
@s_bootargs = private constant [9 x i8] c"bootargs\00"

declare i64 @strlen(ptr)

define internal i64 @dt_byte(i64 %a) {
entry:
  %p = inttoptr i64 %a to ptr
  %c = load i8, ptr %p
  %v = zext i8 %c to i64
  ret i64 %v
}

define internal i64 @be32(i64 %a) {
entry:
  %b0 = call i64 @dt_byte(i64 %a)
  %a1 = add i64 %a, 1
  %b1 = call i64 @dt_byte(i64 %a1)
  %a2 = add i64 %a, 2
  %b2 = call i64 @dt_byte(i64 %a2)
  %a3 = add i64 %a, 3
  %b3 = call i64 @dt_byte(i64 %a3)
  %s0 = shl i64 %b0, 24
  %s1 = shl i64 %b1, 16
  %s2 = shl i64 %b2, 8
  %o0 = or i64 %s0, %s1
  %o1 = or i64 %o0, %s2
  %v = or i64 %o1, %b3
  ret i64 %v
}

; Whether the NUL-terminated name at a is s.
define internal i1 @dt_name_is(i64 %a, ptr %s) {
entry:
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k1, %same ]
  %ak = add i64 %a, %k
  %c = call i64 @dt_byte(i64 %ak)
  %sp = getelementptr i8, ptr %s, i64 %k
  %t8 = load i8, ptr %sp
  %t = zext i8 %t8 to i64
  %eq = icmp eq i64 %c, %t
  br i1 %eq, label %check, label %no
check:
  %end = icmp eq i64 %t, 0
  br i1 %end, label %yes, label %same
same:
  %k1 = add i64 %k, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

define internal i64 @pad4(i64 %n) {
entry:
  %a = add i64 %n, 3
  %r = and i64 %a, -4
  ret i64 %r
}

; Finds /chosen's bootargs in the device tree at dtb, if there is one, and
; takes the arguments from it.
define internal void @boot_args(i64 %dtb) {
entry:
  %null = icmp eq i64 %dtb, 0
  br i1 %null, label %done, label %magic
magic:
  %m = call i64 @be32(i64 %dtb)
  %ok = icmp eq i64 %m, 3490578157                          ; 0xd00dfeed
  br i1 %ok, label %head, label %done
head:
  %ta = add i64 %dtb, 4
  %total = call i64 @be32(i64 %ta)
  %sa = add i64 %dtb, 8
  %ostruct = call i64 @be32(i64 %sa)
  %na = add i64 %dtb, 12
  %ostr = call i64 @be32(i64 %na)
  %p0 = add i64 %dtb, %ostruct
  %end = add i64 %dtb, %total
  %strings = add i64 %dtb, %ostr
  br label %loop
loop:
  %p = phi i64 [ %p0, %head ], [ %bp, %begin ], [ %ep, %leave ], [ %pp, %prop ], [ %np, %nop ]
  %depth = phi i64 [ 0, %head ], [ %bd, %begin ], [ %ed, %leave ], [ %depth, %prop ], [ %depth, %nop ]
  %in = phi i1 [ false, %head ], [ %bin, %begin ], [ %in, %leave ], [ %in, %prop ], [ %in, %nop ]
  %over = icmp uge i64 %p, %end
  br i1 %over, label %done, label %token
token:
  %tok = call i64 @be32(i64 %p)
  switch i64 %tok, label %done [ i64 1, label %begin
                                 i64 2, label %endnode
                                 i64 3, label %propchk
                                 i64 4, label %nop ]
begin:
  %name = add i64 %p, 4
  %top = icmp eq i64 %depth, 1
  %np8 = inttoptr i64 %name to ptr
  %nlen = call i64 @strlen(ptr %np8)
  %isch = call i1 @dt_name_is(i64 %name, ptr @s_chosen)
  %chosen = and i1 %top, %isch
  %bin = or i1 %in, %chosen
  %nl1 = add i64 %nlen, 1
  %npad = call i64 @pad4(i64 %nl1)
  %bp0 = add i64 %p, 4
  %bp = add i64 %bp0, %npad
  %bd = add i64 %depth, 1
  br label %loop
endnode:
  %d2 = icmp eq i64 %depth, 2
  %leaving = and i1 %in, %d2
  br i1 %leaving, label %done, label %leave
leave:
  %ep = add i64 %p, 4
  %ed = sub i64 %depth, 1
  br label %loop
propchk:
  %la = add i64 %p, 4
  %len = call i64 @be32(i64 %la)
  %oa = add i64 %p, 8
  %noff = call i64 @be32(i64 %oa)
  %val = add i64 %p, 12
  %pd2 = icmp eq i64 %depth, 2
  %ours = and i1 %in, %pd2
  br i1 %ours, label %named, label %prop
named:
  %pname = add i64 %strings, %noff
  %isargs = call i1 @dt_name_is(i64 %pname, ptr @s_bootargs)
  br i1 %isargs, label %take, label %prop
take:
  call void @take_args(i64 %val, i64 %len)
  br label %done
prop:
  %lpad = call i64 @pad4(i64 %len)
  %pp0 = add i64 %p, 12
  %pp = add i64 %pp0, %lpad
  br label %loop
nop:
  %np = add i64 %p, 4
  br label %loop
done:
  ret void
}

; Copies the len bytes at val, at most 65,535, into args_buf, and splits
; them at runs of spaces, or at a NUL, into at most 4,096 arguments.
define internal void @take_args(i64 %val, i64 %len) {
entry:
  %big = icmp ugt i64 %len, 65535
  %n = select i1 %big, i64 65535, i64 %len
  %src = inttoptr i64 %val to ptr
  %x = call ptr @memcpy(ptr @args_buf, ptr %src, i64 %n)
  %zp = getelementptr [65536 x i8], ptr @args_buf, i64 0, i64 %n
  store i8 0, ptr %zp
  br label %scan
scan:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %inarg = phi i1 [ false, %entry ], [ %inarg1, %next ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %look, label %finish
look:
  %cp = getelementptr [65536 x i8], ptr @args_buf, i64 0, i64 %i
  %c = load i8, ptr %cp
  %space = icmp eq i8 %c, 32
  %nul = icmp eq i8 %c, 0
  %gap = or i1 %space, %nul
  br i1 %gap, label %cut, label %letter
cut:
  store i8 0, ptr %cp
  br label %next
letter:
  br i1 %inarg, label %next, label %start
start:
  %k = load i64, ptr @arg_n
  %room = icmp ult i64 %k, 4096
  br i1 %room, label %record, label %next
record:
  %ap = getelementptr [4096 x i64], ptr @arg_at, i64 0, i64 %k
  store i64 %i, ptr %ap
  %k1 = add i64 %k, 1
  store i64 %k1, ptr @arg_n
  br label %next
next:
  %inarg1 = phi i1 [ false, %cut ], [ true, %letter ], [ true, %start ], [ true, %record ]
  %i1 = add i64 %i, 1
  br label %scan
finish:
  ret void
}

define i64 @l0_host_arg_count() {
entry:
  %n = load i64, ptr @arg_n
  ret i64 %n
}

; l0rt.ll asks only for an argument below the count.
define ptr @l0_host_arg(i64 %i) {
entry:
  %ap = getelementptr [4096 x i64], ptr @arg_at, i64 0, i64 %i
  %o = load i64, ptr %ap
  %p = getelementptr [65536 x i8], ptr @args_buf, i64 0, i64 %o
  ret ptr %p
}

define ptr @l0_host_setting(ptr %name) {
entry:
  ret ptr null
}

; ----------------------------------------------------------------- regions

; The board's devices, spec section 10.3's table, as QEMU's virt board
; places them: a base and a length each. All are in block 0 of the boot
; map, which is device memory, Device-nGnRnE, so an access goes to the
; device at its width and in order. Anything else, RAM and the runtime's
; heap among it, is no region, and so is any range of the flash, the PCIe
; windows, or the gaps between devices, where QEMU would answer an access
; with an external abort, and so is the GIC, which this file drives itself.
@devices = private constant [10 x i64] [
  i64 150994944, i64 4096,        ; 0x09000000, the PL011
  i64 151060480, i64 4096,        ; 0x09010000, the PL031
  i64 151126016, i64 24,          ; 0x09020000, firmware configuration
  i64 151191552, i64 4096,        ; 0x09030000, the PL061
  i64 167772160, i64 16384 ]      ; 0x0A000000, 32 virtio-mmio transports

; base and len are checked by l0rt.ll: len at least 1, base not negative.
define i64 @l0_host_region(i64 %base, i64 %len) {
entry:
  %end = add i64 %base, %len
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, 5
  br i1 %more, label %look, label %none
look:
  %k = mul i64 %i, 2
  %bp = getelementptr [10 x i64], ptr @devices, i64 0, i64 %k
  %db = load i64, ptr %bp
  %k1 = add i64 %k, 1
  %lp = getelementptr [10 x i64], ptr @devices, i64 0, i64 %k1
  %dl = load i64, ptr %lp
  %de = add i64 %db, %dl
  %from = icmp uge i64 %base, %db
  %to = icmp ule i64 %end, %de
  %within = and i1 %from, %to
  br i1 %within, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
found:
  ret i64 %base
none:
  ret i64 -3
}

define void @l0_host_barrier() {
entry:
  call void asm sideeffect "dsb sy", "~{memory}"()
  ret void
}

; --------------------------------------------------------------- user mode
;
; Spec sections 6.13 and 10.3. Pages come from the pool virt.ld lays out,
; __frames_start to __frames_end, 98,304 of 4 KB, and never go back:
; frames from the bottom, in order, so frame k is the k-th page, and the
; host's own page tables from the top down, so no frame is ever a table,
; until the two meet. A space is
; an index into sp_l1, its level 1 table, and its ASID is the index plus 1,
; so the 255 spaces have 255 ASIDs and moving between them flushes nothing.
;
; Each space's level 1 table maps blocks 0 to 2 as the boot map does, for
; EL1 alone, since the host runs on the thread's tables between traps, and
; block 3, the user range, through a level 2 table of its own; level 3
; tables are made as pages are mapped. Every user entry is a 4 KB page,
; not global, so it is tagged with the space's ASID.

@__frames_start = external global i8
@__frames_end = external global i8

declare void @l0_virt_user_run(ptr, i64)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)

; Read and written by l0_virt_user_run and its trap path.
@l0_virt_user_ctx = global i64 0
@l0_virt_user_sp = global i64 0

@frames_given = internal global i64 0
@tables_used = internal global i64 0
@sp_l1 = internal global [255 x i64] zeroinitializer
@sp_count = internal global i64 0

; Whether the pool has a page left between the frames and the tables.
define internal i1 @pool_room() {
entry:
  %f = load i64, ptr @frames_given
  %t = load i64, ptr @tables_used
  %used = add i64 %f, %t
  %room = icmp ult i64 %used, 98304
  ret i1 %room
}

define internal void @zero_page(i64 %pa) {
entry:
  %p = inttoptr i64 %pa to ptr
  call void @llvm.memset.p0.i64(ptr align 4096 %p, i8 0, i64 4096, i1 false)
  ret void
}

; A zeroed page for a table, from the top of the pool, or 0 when none is
; left.
define internal i64 @pool_page() {
entry:
  %room = call i1 @pool_room()
  br i1 %room, label %take, label %none
none:
  ret i64 0
take:
  %t = load i64, ptr @tables_used
  %t1 = add i64 %t, 1
  store i64 %t1, ptr @tables_used
  %fe = ptrtoint ptr @__frames_end to i64
  %o = shl i64 %t1, 12
  %pa = sub i64 %fe, %o
  call void @zero_page(i64 %pa)
  ret i64 %pa
}

define i64 @l0_host_frame_new() {
entry:
  %room = call i1 @pool_room()
  br i1 %room, label %take, label %out
out:
  ret i64 -5
take:
  %f = load i64, ptr @frames_given
  %f1 = add i64 %f, 1
  store i64 %f1, ptr @frames_given
  %pa = call i64 @frame_pa(i64 %f)
  call void @zero_page(i64 %pa)
  ret i64 %f
}

; Section 10.3: a device on the board reaches a frame at its physical
; address, through the caches as the CPU does, so nothing more is needed.
define i64 @l0_host_frame_address(i64 %f) {
entry:
  %pa = call i64 @frame_pa(i64 %f)
  %nof = icmp eq i64 %pa, 0
  %r = select i1 %nof, i64 2, i64 %pa
  ret i64 %r
}

; The physical address of frame f, or 0 if f is not a frame.
define internal i64 @frame_pa(i64 %f) {
entry:
  %n = load i64, ptr @frames_given
  %in = icmp ult i64 %f, %n
  br i1 %in, label %yes, label %no
yes:
  %fs = ptrtoint ptr @__frames_start to i64
  %o = shl i64 %f, 12
  %pa = add i64 %fs, %o
  ret i64 %pa
no:
  ret i64 0
}

define i64 @l0_host_space_new() {
entry:
  %n = load i64, ptr @sp_count
  %full = icmp uge i64 %n, 255
  br i1 %full, label %out, label %l1
l1:
  %t1 = call i64 @pool_page()
  %no1 = icmp eq i64 %t1, 0
  br i1 %no1, label %out, label %l2
l2:
  %t2 = call i64 @pool_page()
  %no2 = icmp eq i64 %t2, 0
  br i1 %no2, label %out, label %fill
fill:
  %p0 = inttoptr i64 %t1 to ptr
  store i64 27021597764224001, ptr %p0                      ; devices, EL1
  %p1 = getelementptr i64, ptr %p0, i64 1
  store i64 18014399583225605, ptr %p1                      ; RAM, EL1
  %p2 = getelementptr i64, ptr %p0, i64 2
  store i64 18014400656967429, ptr %p2
  %p3 = getelementptr i64, ptr %p0, i64 3
  %d3 = or i64 %t2, 3                                       ; the user range
  store i64 %d3, ptr %p3
  %sp = getelementptr [255 x i64], ptr @sp_l1, i64 0, i64 %n
  store i64 %t1, ptr %sp
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @sp_count
  call void asm sideeffect "dsb ishst", "~{memory}"()
  ret i64 %n
out:
  ret i64 -5
}

; The level 1 table of space s, or 0 if s is not a space.
define internal i64 @space_l1(i64 %s) {
entry:
  %n = load i64, ptr @sp_count
  %in = icmp ult i64 %s, %n
  br i1 %in, label %yes, label %no
yes:
  %sp = getelementptr [255 x i64], ptr @sp_l1, i64 0, i64 %s
  %t = load i64, ptr %sp
  ret i64 %t
no:
  ret i64 0
}

; Whether va is a page of the user range, 0xC0000000 up to 0x100000000.
define internal i1 @user_page(i64 %va) {
entry:
  %off = and i64 %va, 4095
  %aligned = icmp eq i64 %off, 0
  %lo = icmp uge i64 %va, 3221225472
  %hi = icmp ult i64 %va, 4294967296
  %in = and i1 %lo, %hi
  %r = and i1 %aligned, %in
  ret i1 %r
}

; The address of the level 3 entry for the user address va in the space
; whose level 1 table is l1, making its level 3 table if make is true: 0 if
; the table is missing and not made, or no page is left to make it.
define internal i64 @l3_entry(i64 %l1, i64 %va, i1 %make) {
entry:
  %e3 = add i64 %l1, 24
  %p3 = inttoptr i64 %e3 to ptr
  %d3 = load i64, ptr %p3
  %l2 = and i64 %d3, 281474976706560
  %s2 = lshr i64 %va, 21
  %i2 = and i64 %s2, 511
  %o2 = shl i64 %i2, 3
  %e2 = add i64 %l2, %o2
  %p2 = inttoptr i64 %e2 to ptr
  %d2 = load i64, ptr %p2
  %has = icmp ne i64 %d2, 0
  br i1 %has, label %have, label %missing
missing:
  br i1 %make, label %alloc, label %none
alloc:
  %t = call i64 @pool_page()
  %nopage = icmp eq i64 %t, 0
  br i1 %nopage, label %none, label %link
link:
  %dt = or i64 %t, 3
  store i64 %dt, ptr %p2
  br label %have
have:
  %d = phi i64 [ %d2, %entry ], [ %dt, %link ]
  %l3 = and i64 %d, 281474976706560
  %s3 = lshr i64 %va, 12
  %i3 = and i64 %s3, 511
  %o3 = shl i64 %i3, 3
  %e = add i64 %l3, %o3
  ret i64 %e
none:
  ret i64 0
}

; A user page's descriptor bits for perm, spec section 6.13: valid, a page,
; normal memory (MAIR attribute 1), inner shareable, accessed, not global;
; AP 01, read and write at EL0, or 11, read only; never executable at EL1
; (PXN), and at EL0 (UXN) unless perm says so.
define internal i64 @page_bits(i64 %perm) {
entry:
  %w = and i64 %perm, 1
  %x = and i64 %perm, 2
  %rw = icmp ne i64 %w, 0
  %ap = select i1 %rw, i64 3911, i64 4039
  %ex = icmp ne i64 %x, 0
  %xn = select i1 %ex, i64 9007199254740992, i64 27021597764222976
  %d = or i64 %ap, %xn
  ret i64 %d
}

define i64 @l0_host_space_map(i64 %s, i64 %va, i64 %f, i64 %perm) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %frame
frame:
  %pa = call i64 @frame_pa(i64 %f)
  %nof = icmp eq i64 %pa, 0
  br i1 %nof, label %e2, label %access
access:
  %okp = icmp ult i64 %perm, 4
  br i1 %okp, label %where, label %e3
where:
  %okv = call i1 @user_page(i64 %va)
  br i1 %okv, label %entry3, label %e4
entry3:
  %e = call i64 @l3_entry(i64 %l1, i64 %va, i1 true)
  %noroom = icmp eq i64 %e, 0
  br i1 %noroom, label %full, label %free
free:
  %ep = inttoptr i64 %e to ptr
  %old = load i64, ptr %ep
  %taken = icmp ne i64 %old, 0
  br i1 %taken, label %e5, label %map
map:
  %bits = call i64 @page_bits(i64 %perm)
  %d = or i64 %pa, %bits
  store i64 %d, ptr %ep
  call void asm sideeffect "dsb ishst\0Aisb", "~{memory}"()
  ret i64 0
e1:
  ret i64 1
e2:
  ret i64 2
e3:
  ret i64 3
e4:
  ret i64 4
e5:
  ret i64 5
full:
  ret i64 -5
}

; The pages of [base, base + len), as l0_host_region checks it, at the user
; pages from va: device memory, MAIR attribute 0, read and write at EL0,
; never executable. Every page is checked before any is mapped.
define i64 @l0_host_space_map_device(i64 %s, i64 %va, i64 %base, i64 %len) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %args
args:
  %short = icmp slt i64 %len, 1
  %neg = icmp slt i64 %base, 0
  %bad = or i1 %short, %neg
  br i1 %bad, label %nodev, label %dev
dev:
  %r = call i64 @l0_host_region(i64 %base, i64 %len)
  %isdev = icmp sge i64 %r, 0
  br i1 %isdev, label %count, label %nodev
count:
  %first = and i64 %base, -4096
  %end = add i64 %base, %len
  %last0 = sub i64 %end, 1
  %last = and i64 %last0, -4096
  %span = sub i64 %last, %first
  %n0 = lshr i64 %span, 12
  %n = add i64 %n0, 1
  %okv = call i1 @user_page(i64 %va)
  %top0 = shl i64 %n0, 12
  %top = add i64 %va, %top0
  %okt = call i1 @user_page(i64 %top)
  %ok = and i1 %okv, %okt
  br i1 %ok, label %check, label %e4
check:
  %k = phi i64 [ 0, %count ], [ %k1, %clear ]
  %more = icmp ult i64 %k, %n
  br i1 %more, label %look, label %map
look:
  %ko = shl i64 %k, 12
  %pv = add i64 %va, %ko
  %e = call i64 @l3_entry(i64 %l1, i64 %pv, i1 true)
  %noroom = icmp eq i64 %e, 0
  br i1 %noroom, label %full, label %peek
peek:
  %ep = inttoptr i64 %e to ptr
  %old = load i64, ptr %ep
  %taken = icmp ne i64 %old, 0
  br i1 %taken, label %e5, label %clear
clear:
  %k1 = add i64 %k, 1
  br label %check
map:
  %j = phi i64 [ 0, %check ], [ %j1, %put ]
  %mmore = icmp ult i64 %j, %n
  br i1 %mmore, label %put, label %done
put:
  %jo = shl i64 %j, 12
  %qv = add i64 %va, %jo
  %qe = call i64 @l3_entry(i64 %l1, i64 %qv, i1 false)
  %qp = inttoptr i64 %qe to ptr
  %qa = add i64 %first, %jo
  %qd = or i64 %qa, 27021597764226115
  store i64 %qd, ptr %qp
  %j1 = add i64 %j, 1
  br label %map
done:
  call void asm sideeffect "dsb ishst\0Aisb", "~{memory}"()
  ret i64 0
e1:
  ret i64 1
e4:
  ret i64 4
e5:
  ret i64 5
nodev:
  ret i64 -3
full:
  ret i64 -5
}

; The physical address of the user address va in the space whose level 1
; table is l1, if it is on a page space_map mapped, or 0: never a device
; page, which only space_map_device maps, with MAIR attribute 0.
define internal i64 @user_pa(i64 %l1, i64 %va) {
entry:
  %page = and i64 %va, -4096
  %e = call i64 @l3_entry(i64 %l1, i64 %page, i1 false)
  %none = icmp eq i64 %e, 0
  br i1 %none, label %no, label %look
look:
  %ep = inttoptr i64 %e to ptr
  %d = load i64, ptr %ep
  %v = and i64 %d, 3
  %valid = icmp eq i64 %v, 3
  %attr = and i64 %d, 28
  %normal = icmp eq i64 %attr, 4
  %ok = and i1 %valid, %normal
  br i1 %ok, label %yes, label %no
yes:
  %frame = and i64 %d, 281474976706560
  %off = and i64 %va, 4095
  %pa = add i64 %frame, %off
  ret i64 %pa
no:
  ret i64 0
}

; Cleans the data cache to the point of unification over [pa, pa + n), and
; then invalidates the instruction cache, so that bytes copied into a
; space can be run there.
define internal void @code_sync(i64 %pa, i64 %n) {
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

; Copies n bytes between buf and the space from va, into it when dir is 1,
; out of it when 0, after checking that every byte is on a page space_map
; mapped. An empty copy checks only that s is a space.
define i64 @l0_host_space_copy(i64 %s, i64 %va, ptr %buf, i64 %n, i64 %dir) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %empty
empty:
  %zero = icmp eq i64 %n, 0
  br i1 %zero, label %done, label %range
range:
  %lo = icmp uge i64 %va, 3221225472
  %hi = icmp ult i64 %va, 4294967296
  %room = sub i64 4294967296, %va
  %fits = icmp ule i64 %n, %room
  %in0 = and i1 %lo, %hi
  %in = and i1 %in0, %fits
  br i1 %in, label %check, label %e6
check:
  %c = phi i64 [ %va, %range ], [ %c1, %cnext ]
  %end = add i64 %va, %n
  %cmore = icmp ult i64 %c, %end
  br i1 %cmore, label %clook, label %copy
clook:
  %cpa = call i64 @user_pa(i64 %l1, i64 %c)
  %cno = icmp eq i64 %cpa, 0
  br i1 %cno, label %e6, label %cnext
cnext:
  %cpage = and i64 %c, -4096
  %c1 = add i64 %cpage, 4096
  br label %check
copy:
  %v = phi i64 [ %va, %check ], [ %v1, %moved ]
  %bo = phi i64 [ 0, %check ], [ %bo1, %moved ]
  %left = sub i64 %n, %bo
  %more = icmp sgt i64 %left, 0
  br i1 %more, label %chunk, label %done
chunk:
  %pa = call i64 @user_pa(i64 %l1, i64 %v)
  %poff = and i64 %v, 4095
  %prest = sub i64 4096, %poff
  %small = icmp ult i64 %left, %prest
  %k = select i1 %small, i64 %left, i64 %prest
  %pp = inttoptr i64 %pa to ptr
  %bp = getelementptr i8, ptr %buf, i64 %bo
  %in1 = icmp eq i64 %dir, 1
  br i1 %in1, label %into, label %outof
into:
  %x = call ptr @memcpy(ptr %pp, ptr %bp, i64 %k)
  call void @code_sync(i64 %pa, i64 %k)
  br label %moved
outof:
  %y = call ptr @memcpy(ptr %bp, ptr %pp, i64 %k)
  br label %moved
moved:
  %v1 = add i64 %v, %k
  %bo1 = add i64 %bo, %k
  br label %copy
done:
  ret i64 0
e1:
  ret i64 1
e6:
  ret i64 6
}

; Runs the thread whose context is the n words at words, in space s, until
; it traps. Only the flags of its pstate are its own: it runs at EL0t, with
; interrupts unmasked. An interrupt is taken before returning, its number
; in word 36; a spurious one sends the thread straight back.
define i64 @l0_host_user_run(i64 %s, ptr %words, i64 %n) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %len
len:
  %right = icmp eq i64 %n, 104
  br i1 %right, label %prep, label %e7
prep:
  %asid0 = add i64 %s, 1
  %asid = shl i64 %asid0, 48
  %ttbr = or i64 %l1, %asid
  %pp = getelementptr i64, ptr %words, i64 33
  br label %run
run:
  %ps = load i64, ptr %pp
  %flags = and i64 %ps, 4026531840
  store i64 %flags, ptr %pp
  call void @l0_virt_user_run(ptr %words, i64 %ttbr)
  %kp = getelementptr i64, ptr %words, i64 35
  %kind = load i64, ptr %kp
  %irq = icmp eq i64 %kind, 1
  br i1 %irq, label %take, label %done
take:
  %num = call i64 @irq_take()
  %spurious = icmp slt i64 %num, 0
  br i1 %spurious, label %run, label %record
record:
  %np = getelementptr i64, ptr %words, i64 36
  store i64 %num, ptr %np
  br label %done
done:
  ret i64 0
e1:
  ret i64 1
e7:
  ret i64 7
}

; -------------------------------------------------------------- interrupts
;
; Spec sections 6.14 and 10.3. The GICv2's distributor is at 0x08000000
; and its CPU interface at 0x08010000, and neither is a region, so only
; this file touches them. The CPU interface runs with EOImode 1: taking an
; interrupt reads its acknowledge register and at once writes its
; end-of-interrupt register, which drops the running priority so that
; others can come, and interrupt_done writes its deactivate register, which
; lets the same one come again. That is section 6.14's taken until ended.
; Every interrupt has priority 0, and the program runs with interrupts
; masked at EL1, so one arrives only at interrupt_wait's wfi or while a
; thread runs. Interrupt 0 is the virtual timer's, the GIC's 27; a
; device's number is its GIC ID.

@irq_taken = internal global [1024 x i8] zeroinitializer
@irq_enabled = internal global [1024 x i8] zeroinitializer
@irq_count = internal global i64 0

define internal void @gic_init() {
entry:
  call void @mmio_w32(i64 134217728, i32 1)                 ; GICD_CTLR, on
  call void @mmio_w32(i64 134283268, i32 240)               ; GICC_PMR
  call void @mmio_w32(i64 134283264, i32 513)               ; GICC_CTLR, on, EOImode 1
  ret void
}

define internal void @mmio_w32(i64 %a, i32 %v) {
entry:
  %p = inttoptr i64 %a to ptr
  store volatile i32 %v, ptr %p
  ret void
}

define internal void @mmio_w8(i64 %a, i8 %v) {
entry:
  %p = inttoptr i64 %a to ptr
  store volatile i8 %v, ptr %p
  ret void
}

define internal i32 @mmio_r32(i64 %a) {
entry:
  %p = inttoptr i64 %a to ptr
  %v = load volatile i32, ptr %p
  ret i32 %v
}

; The GIC ID of interrupt n, or -1 if the host gives no interrupt n: the
; timer's, 0, is 27; the PL011's, PL031's, and PL061's are 33, 34, and 39,
; and the virtio-mmio transports' 48 to 79.
define internal i64 @irq_id(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  br i1 %timer, label %t, label %dev
t:
  ret i64 27
dev:
  %uart = icmp eq i64 %n, 33
  %rtc = icmp eq i64 %n, 34
  %gpio = icmp eq i64 %n, 39
  %lo = icmp sge i64 %n, 48
  %hi = icmp sle i64 %n, 79
  %virtio = and i1 %lo, %hi
  %a = or i1 %uart, %rtc
  %b = or i1 %gpio, %virtio
  %ok = or i1 %a, %b
  %r = select i1 %ok, i64 %n, i64 -1
  ret i64 %r
}

define i64 @l0_host_interrupt_enable(i64 %n) {
entry:
  %id = call i64 @irq_id(i64 %n)
  %none = icmp slt i64 %id, 0
  br i1 %none, label %out, label %on
out:
  ret i64 -3
on:
  %ep = getelementptr [1024 x i8], ptr @irq_enabled, i64 0, i64 %id
  %was = load i8, ptr %ep
  %fresh = icmp eq i8 %was, 0
  br i1 %fresh, label %count, label %done
count:
  store i8 1, ptr %ep
  %c = load i64, ptr @irq_count
  %c1 = add i64 %c, 1
  store i64 %c1, ptr @irq_count
  %spi = icmp uge i64 %id, 32
  br i1 %spi, label %target, label %enable
target:
  %ta = add i64 134219776, %id                              ; GICD_ITARGETSR, CPU 0
  call void @mmio_w8(i64 %ta, i8 1)
  br label %enable
enable:
  %word = lshr i64 %id, 5
  %wo = shl i64 %word, 2
  %ra = add i64 134217984, %wo                              ; GICD_ISENABLER
  %bit = and i64 %id, 31
  %m = shl i64 1, %bit
  %m32 = trunc i64 %m to i32
  call void @mmio_w32(i64 %ra, i32 %m32)
  call void asm sideeffect "dsb sy\0Aisb", "~{memory}"()
  br label %done
done:
  ret i64 0
}

; Takes the interrupt the CPU interface signals, and returns its number, or
; -1 for a spurious one, which needs no end.
define internal i64 @irq_take() {
entry:
  %iar = call i32 @mmio_r32(i64 134283276)                  ; GICC_IAR
  %id32 = and i32 %iar, 1023
  %id = zext i32 %id32 to i64
  %spurious = icmp uge i64 %id, 1020
  br i1 %spurious, label %none, label %take
none:
  ret i64 -1
take:
  call void @mmio_w32(i64 134283280, i32 %iar)              ; GICC_EOIR, priority drop
  %tp = getelementptr [1024 x i8], ptr @irq_taken, i64 0, i64 %id
  store i8 1, ptr %tp
  %timer = icmp eq i64 %id, 27
  %n = select i1 %timer, i64 0, i64 %id
  ret i64 %n
}

define i64 @l0_host_interrupt_wait() {
entry:
  %c = load i64, ptr @irq_count
  %none = icmp eq i64 %c, 0
  br i1 %none, label %out, label %wait
out:
  ret i64 -5
wait:
  call void asm sideeffect "dsb sy\0Awfi", "~{memory}"()
  %n = call i64 @irq_take()
  %spurious = icmp slt i64 %n, 0
  br i1 %spurious, label %wait, label %got
got:
  ret i64 %n
}

define i64 @l0_host_interrupt_done(i64 %n) {
entry:
  %id = call i64 @irq_id(i64 %n)
  %none = icmp slt i64 %id, 0
  br i1 %none, label %e8, label %look
look:
  %tp = getelementptr [1024 x i8], ptr @irq_taken, i64 0, i64 %id
  %t = load i8, ptr %tp
  %taken = icmp ne i8 %t, 0
  br i1 %taken, label %end, label %e8
end:
  store i8 0, ptr %tp
  %id32 = trunc i64 %id to i32
  call void @mmio_w32(i64 134287360, i32 %id32)             ; GICC_DIR
  ret i64 0
e8:
  ret i64 8
}

; Spec section 9.2: no kernel beneath the program on the bare board.
define i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %b, i64 %c) {
entry:
  ret i64 -3
}

; The virtual timer's compare value for t nanoseconds, rounded up, so that
; it fires no earlier than clock_ns reads t; a negative t disables it.
define i64 @l0_host_timer_at(i64 %t) {
entry:
  %off = icmp slt i64 %t, 0
  br i1 %off, label %disarm, label %arm
disarm:
  call void asm sideeffect "msr cntv_ctl_el0, $0\0Aisb", "r"(i64 0)
  ret i64 0
arm:
  %frq = call i64 asm "mrs $0, cntfrq_el0", "=r"()
  %nofrq = icmp eq i64 %frq, 0
  br i1 %nofrq, label %out, label %set
out:
  ret i64 -3
set:
  %sec = udiv i64 %t, 1000000000
  %rem = urem i64 %t, 1000000000
  %whole = mul i64 %sec, %frq
  %part0 = mul i64 %rem, %frq
  %part1 = add i64 %part0, 999999999
  %part = udiv i64 %part1, 1000000000
  %cval = add i64 %whole, %part
  call void asm sideeffect "msr cntv_cval_el0, $0", "r"(i64 %cval)
  call void asm sideeffect "msr cntv_ctl_el0, $0\0Aisb", "r"(i64 1)
  ret i64 0
}
