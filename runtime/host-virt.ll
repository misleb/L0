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
; Memory, with QEMU's -m 2G (RAM is 0x40000000 to 0xC0000000):
;   0x40000000  the device tree, put there by QEMU
;   0x40080000  the image: code, data, bss
;   0x4FFFFFF8  standard input's length, a word, written by QEMU's loader
;   0x50000000  standard input's bytes, loaded by QEMU's loader
;   0x58000000  the heap, to 0xB0000000
;   0xB0000000  the stack, 256 MB, growing down from 0xC0000000
;
; Standard input is the bytes QEMU loaded, since a serial line has no end
; of input; with none loaded the length word is 0 and input is empty.
; Standard output is the PL011 serial port at 0x09000000. Standard error
; and the exit status reach the host by semihosting, so the three stay
; apart on a board with one serial line. As section 9.2 says, there are no
; files, no arguments, and no environment. The clock is the generic timer.
; The board's devices are what a program may open as regions (spec section
; 6.12), the serial port among them.
;
; An exception the runtime does not expect is a bug in it, and is reported
; on standard error, with the registers that say where, and stops with
; status 99.

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
module asm "  ldr x0, =l0_virt_vectors"
module asm "  msr vbar_el1, x0"
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
module asm "  ldr x1, =0x1005"
module asm "  orr x0, x0, x1"
module asm "  bic x0, x0, #2"
module asm "  msr sctlr_el1, x0"
module asm "  isb"
module asm "  bl l0_virt_main"
module asm "1: b 1b"
module asm ".balign 2048"
module asm "l0_virt_vectors:"
module asm ".rept 16"
module asm ".balign 128"
module asm "  b l0_virt_trap_entry"
module asm ".endr"
module asm "l0_virt_trap_entry:"
module asm "  mrs x0, esr_el1"
module asm "  mrs x1, elr_el1"
module asm "  mrs x2, far_el1"
module asm "  bl l0_virt_trap"
module asm "2: b 2b"

; The boot code enables floating point and SIMD, which LLVM may use for
; copies, and the MMU, with this identity map in 1 GB blocks at level 1
; (TCR T0SZ 32, 4 KB granule). Block 0 holds the devices, MAIR attribute 0,
; Device-nGnRnE; blocks 1 and 2 are the RAM, attribute 1, normal
; write-back, inner shareable. With the MMU off every access would be to
; device memory, where an unaligned one faults.
@l0_virt_pt = global [4 x i64] [i64 1025, i64 1073743621, i64 2147485445, i64 0], align 4096

@__stack_top = external global i8
@__stack_bottom = external global i8

; Defined by runtime/l0rt.ll. Spec section 10.3.
declare i64 @l0_rt_run(i64)

; Defined by runtime/freestanding.ll.
declare ptr @memcpy(ptr, ptr, i64)

; Called by _start on the boot stack. l0_rt_run's frame is a little below
; the top, so the size it is given leaves 64 KB for what lies above it.
define void @l0_virt_main() noreturn {
entry:
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

define i64 @l0_host_arg_count() {
entry:
  ret i64 0
}

define ptr @l0_host_arg(i64 %i) {
entry:
  ret ptr null
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
; with an external abort.
@devices = private constant [16 x i64] [
  i64 134217728, i64 65536,       ; 0x08000000, the GIC's distributor
  i64 134283264, i64 65536,       ; 0x08010000, its CPU interface
  i64 134348800, i64 4096,        ; 0x08020000, its GICv2m frame
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
  %more = icmp ult i64 %i, 8
  br i1 %more, label %look, label %none
look:
  %k = mul i64 %i, 2
  %bp = getelementptr [16 x i64], ptr @devices, i64 0, i64 %k
  %db = load i64, ptr %bp
  %k1 = add i64 %k, 1
  %lp = getelementptr [16 x i64], ptr @devices, i64 0, i64 %k1
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
