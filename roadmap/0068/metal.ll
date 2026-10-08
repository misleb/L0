; metal.ll -- roadmap item 0068's prototype: what runtime/l0rt.ll needs from
; libc, for QEMU's aarch64 virt board with no operating system. Linked with
; l0rt.ll unchanged and a compiled program, by metal.ld.
;
; Memory, with -m 2G (RAM is 0x40000000 to 0xC0000000):
;   0x40000000  device tree, put there by QEMU
;   0x40080000  the image: code, data, bss
;   0x4FFFFFF8  standard input's length, a word, written by QEMU's loader
;   0x50000000  standard input's bytes, loaded by QEMU's loader
;   0x58000000  the heap, to 0xB0000000
;   0xB0000000  the stack, 256 MB, growing down from 0xC0000000
;
; Standard output is the PL011 at 0x09000000. Standard error and the exit
; status go to the host by semihosting, so the two outputs stay apart on a
; board with one serial line. Nothing else exists: every file operation
; fails, and errno cannot be read, since dlsym finds nothing.

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
module asm "  ldr x0, =metal_vectors"
module asm "  msr vbar_el1, x0"
module asm "  mov x0, #0xff00"
module asm "  msr mair_el1, x0"
module asm "  ldr x0, =0x803520"
module asm "  msr tcr_el1, x0"
module asm "  ldr x0, =metal_pt"
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
module asm "  bl metal_main"
module asm "1: b 1b"
module asm ".balign 2048"
module asm "metal_vectors:"
module asm ".rept 16"
module asm ".balign 128"
module asm "  b metal_trap"
module asm ".endr"
module asm "metal_trap:"
module asm "  mrs x0, esr_el1"
module asm "  mrs x1, elr_el1"
module asm "  mrs x2, far_el1"
module asm "  bl metal_fault"
module asm "2: b 2b"

; An identity map in 1 GB blocks at level 1 (TCR T0SZ 32, 4 KB granule).
; Block 0 holds the devices, MAIR attribute 0, Device-nGnRnE; blocks 1 and 2
; are the RAM, attribute 1, normal write-back, inner shareable. With the MMU
; off every access would be to device memory, where an unaligned one faults.
@metal_pt = global [4 x i64] [i64 1025, i64 1073743621, i64 2147485445, i64 0], align 4096

@__stack_top = external global i8
@__heap_start = external global i8
@__heap_end = external global i8

declare i32 @main(i32, ptr)
declare i64 @llvm.ctlz.i64(i64, i1)

@prog_name = private constant [3 x i8] c"l0\00"
@argv0 = internal global [2 x ptr] [ptr @prog_name, ptr null]

define void @metal_main() noreturn {
entry:
  %st = call i32 @main(i32 1, ptr @argv0)
  call void @_exit(i32 %st)
  unreachable
}

@m_trap = private constant [24 x i8] c"l0-metal: exception esr="
@m_elr = private constant [5 x i8] c" elr="
@m_far = private constant [5 x i8] c" far="
@m_nl = private constant [1 x i8] c"\0A"
@hexd = private constant [16 x i8] c"0123456789abcdef"

define internal void @put_hex(i64 %v) {
entry:
  %buf = alloca [16 x i8]
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %sh0 = sub i64 15, %i
  %sh = mul i64 %sh0, 4
  %nib = lshr i64 %v, %sh
  %d = and i64 %nib, 15
  %dp = getelementptr [16 x i8], ptr @hexd, i64 0, i64 %d
  %c = load i8, ptr %dp
  %bp = getelementptr [16 x i8], ptr %buf, i64 0, i64 %i
  store i8 %c, ptr %bp
  %i1 = add i64 %i, 1
  %more = icmp ult i64 %i1, 16
  br i1 %more, label %loop, label %done
done:
  %w = call i64 @write(i32 2, ptr %buf, i64 16)
  ret void
}

define void @metal_fault(i64 %esr, i64 %elr, i64 %far) noreturn {
entry:
  %a = call i64 @write(i32 2, ptr @m_trap, i64 24)
  call void @put_hex(i64 %esr)
  %b = call i64 @write(i32 2, ptr @m_elr, i64 5)
  call void @put_hex(i64 %elr)
  %c = call i64 @write(i32 2, ptr @m_far, i64 5)
  call void @put_hex(i64 %far)
  %d = call i64 @write(i32 2, ptr @m_nl, i64 1)
  call void @_exit(i32 99)
  unreachable
}

; ------------------------------------------------------------ semihosting

define internal i64 @semi(i64 %op, ptr %blk) {
entry:
  %r = call i64 asm sideeffect "hlt #0xf000", "={x0},{x0},{x1},~{memory}"(i64 %op, ptr %blk)
  ret i64 %r
}

; ADP_Stopped_ApplicationExit, with the status as its subcode, which QEMU
; makes its own exit status.
define void @_exit(i32 %status) noreturn {
entry:
  %blk = alloca [2 x i64], align 8
  store i64 131110, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  %s = sext i32 %status to i64
  store i64 %s, ptr %p1
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

; ------------------------------------------------------------------ uart

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

; ----------------------------------------------------------------- read/write

@in_pos = internal global i64 0

define i64 @read(i32 %fd, ptr %buf, i64 %n) {
entry:
  %is0 = icmp eq i32 %fd, 0
  br i1 %is0, label %input, label %bad
bad:
  ret i64 -1
input:
  %len = load i64, ptr inttoptr (i64 1342177272 to ptr)
  %pos = load i64, ptr @in_pos
  %left = sub i64 %len, %pos
  %less = icmp ult i64 %left, %n
  %k = select i1 %less, i64 %left, i64 %n
  %src0 = getelementptr i8, ptr inttoptr (i64 1342177280 to ptr), i64 %pos
  %x = call ptr @memcpy(ptr %buf, ptr %src0, i64 %k)
  %np = add i64 %pos, %k
  store i64 %np, ptr @in_pos
  ret i64 %k
}

define i64 @write(i32 %fd, ptr %buf, i64 %n) {
entry:
  %is1 = icmp eq i32 %fd, 1
  br i1 %is1, label %uart, label %not1
not1:
  %is2 = icmp eq i32 %fd, 2
  br i1 %is2, label %err, label %bad
bad:
  ret i64 -1
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
  ret i64 %wrote
}

; ------------------------------------------------------------------ memory

; Power-of-two size classes from 16 bytes, each block preceded by a 16-byte
; header holding its class. Freed blocks go on their class's list; the rest
; is a bump pointer over the heap. Enough for a prototype: a block is never
; split or merged.
@heap_cur = internal global i64 0
@free_lists = internal global [64 x i64] zeroinitializer

define internal i64 @size_class(i64 %n) {
entry:
  %small = icmp ule i64 %n, 16
  br i1 %small, label %min, label %calc
min:
  ret i64 4
calc:
  %m = sub i64 %n, 1
  %z = call i64 @llvm.ctlz.i64(i64 %m, i1 false)
  %k = sub i64 64, %z
  ret i64 %k
}

define ptr @malloc(i64 %n) {
entry:
  %k = call i64 @size_class(i64 %n)
  %lp = getelementptr [64 x i64], ptr @free_lists, i64 0, i64 %k
  %head = load i64, ptr %lp
  %have = icmp ne i64 %head, 0
  br i1 %have, label %reuse, label %bump
reuse:
  %hp = inttoptr i64 %head to ptr
  %next = load i64, ptr %hp
  store i64 %next, ptr %lp
  %hdr = sub i64 %head, 16
  %hdrp = inttoptr i64 %hdr to ptr
  store i64 %k, ptr %hdrp
  ret ptr %hp
bump:
  %cur0 = load i64, ptr @heap_cur
  %fresh = icmp eq i64 %cur0, 0
  %hs = ptrtoint ptr @__heap_start to i64
  %cur = select i1 %fresh, i64 %hs, i64 %cur0
  %size = shl i64 1, %k
  %total = add i64 %size, 16
  %end = add i64 %cur, %total
  %he = ptrtoint ptr @__heap_end to i64
  %over = icmp ugt i64 %end, %he
  br i1 %over, label %oom, label %take
oom:
  ret ptr null
take:
  store i64 %end, ptr @heap_cur
  %cp = inttoptr i64 %cur to ptr
  store i64 %k, ptr %cp
  %u = add i64 %cur, 16
  %up = inttoptr i64 %u to ptr
  ret ptr %up
}

define void @free(ptr %p) {
entry:
  %null = icmp eq ptr %p, null
  br i1 %null, label %done, label %put
put:
  %hp = getelementptr i8, ptr %p, i64 -16
  %k = load i64, ptr %hp
  %lp = getelementptr [64 x i64], ptr @free_lists, i64 0, i64 %k
  %head = load i64, ptr %lp
  store i64 %head, ptr %p
  %pi = ptrtoint ptr %p to i64
  store i64 %pi, ptr %lp
  br label %done
done:
  ret void
}

define ptr @realloc(ptr %p, i64 %n) {
entry:
  %null = icmp eq ptr %p, null
  br i1 %null, label %fresh, label %have
fresh:
  %f = call ptr @malloc(i64 %n)
  ret ptr %f
have:
  %hp = getelementptr i8, ptr %p, i64 -16
  %k = load i64, ptr %hp
  %cap = shl i64 1, %k
  %fits = icmp ule i64 %n, %cap
  br i1 %fits, label %same, label %move
same:
  ret ptr %p
move:
  %q = call ptr @malloc(i64 %n)
  %failed = icmp eq ptr %q, null
  br i1 %failed, label %oom, label %copy
oom:
  ret ptr null
copy:
  %x = call ptr @memcpy(ptr %q, ptr %p, i64 %cap)
  call void @free(ptr %p)
  ret ptr %q
}

; Byte loops, kept from being recognized as calls to themselves.
define ptr @memcpy(ptr %d, ptr %s, i64 %n) #0 {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr i8, ptr %s, i64 %i
  %c = load i8, ptr %sp
  %dp = getelementptr i8, ptr %d, i64 %i
  store i8 %c, ptr %dp
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret ptr %d
}

define ptr @memmove(ptr %d, ptr %s, i64 %n) #0 {
entry:
  %di = ptrtoint ptr %d to i64
  %si = ptrtoint ptr %s to i64
  %fwd = icmp ule i64 %di, %si
  br i1 %fwd, label %forward, label %back
forward:
  %x = call ptr @memcpy(ptr %d, ptr %s, i64 %n)
  ret ptr %d
back:
  br label %bloop
bloop:
  %i = phi i64 [ %n, %back ], [ %j, %bbody ]
  %more = icmp ugt i64 %i, 0
  br i1 %more, label %bbody, label %done
bbody:
  %j = sub i64 %i, 1
  %sp = getelementptr i8, ptr %s, i64 %j
  %c = load i8, ptr %sp
  %dp = getelementptr i8, ptr %d, i64 %j
  store i8 %c, ptr %dp
  br label %bloop
done:
  ret ptr %d
}

define ptr @memset(ptr %d, i32 %v, i64 %n) #0 {
entry:
  %b = trunc i32 %v to i8
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %dp = getelementptr i8, ptr %d, i64 %i
  store i8 %b, ptr %dp
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret ptr %d
}

define i32 @memcmp(ptr %a, ptr %b, i64 %n) #0 {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %same ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %equal
body:
  %ap = getelementptr i8, ptr %a, i64 %i
  %ac = load i8, ptr %ap
  %bp = getelementptr i8, ptr %b, i64 %i
  %bc = load i8, ptr %bp
  %eq = icmp eq i8 %ac, %bc
  br i1 %eq, label %same, label %differ
same:
  %i1 = add i64 %i, 1
  br label %loop
differ:
  %az = zext i8 %ac to i32
  %bz = zext i8 %bc to i32
  %d = sub i32 %az, %bz
  ret i32 %d
equal:
  ret i32 0
}

define i32 @bcmp(ptr %a, ptr %b, i64 %n) #0 {
entry:
  %r = call i32 @memcmp(ptr %a, ptr %b, i64 %n)
  ret i32 %r
}

attributes #0 = { "no-builtins" }

; ------------------------------------------------------------------- clock

define i32 @clock_gettime(i32 %clk, ptr %ts) {
entry:
  %cnt = call i64 asm sideeffect "isb\0Amrs $0, cntvct_el0", "=r"()
  %frq = call i64 asm "mrs $0, cntfrq_el0", "=r"()
  %sec = udiv i64 %cnt, %frq
  %rem = urem i64 %cnt, %frq
  %remns = mul i64 %rem, 1000000000
  %ns = udiv i64 %remns, %frq
  store i64 %sec, ptr %ts
  %p1 = getelementptr i64, ptr %ts, i64 1
  store i64 %ns, ptr %p1
  ret i32 0
}

; ------------------------------------------------- the stack, and threads

; No threads: pthread_create fails, so l0rt.ll's main runs the program on
; the boot stack, sized by getrlimit, less what lies above main's frame.
define i32 @getrlimit(i32 %r, ptr %rl) {
entry:
  store i64 268173312, ptr %rl
  %p1 = getelementptr i64, ptr %rl, i64 1
  store i64 268435456, ptr %p1
  ret i32 0
}

define i32 @pthread_attr_init(ptr %a) {
entry:
  ret i32 0
}

define i32 @pthread_attr_setstacksize(ptr %a, i64 %n) {
entry:
  ret i32 0
}

define i32 @pthread_create(ptr %t, ptr %a, ptr %f, ptr %arg) {
entry:
  ret i32 11
}

define i32 @pthread_join(i64 %t, ptr %r) {
entry:
  ret i32 0
}

; ---------------------------------------------- what this board does not have

define ptr @getenv(ptr %name) {
entry:
  ret ptr null
}

define i64 @strtol(ptr %s, ptr %end, i32 %base) {
entry:
  ret i64 0
}

define ptr @signal(i32 %sig, ptr %h) {
entry:
  ret ptr null
}

define ptr @dlopen(ptr %name, i32 %flags) {
entry:
  ret ptr null
}

define ptr @dlsym(ptr %h, ptr %name) {
entry:
  ret ptr null
}

; The standard descriptors are always open: dup of one gives 3, which close
; accepts. No other descriptor exists.
define i32 @dup(i32 %fd) {
entry:
  %std = icmp ult i32 %fd, 3
  %r = select i1 %std, i32 3, i32 -1
  ret i32 %r
}

define i32 @close(i32 %fd) {
entry:
  %ok = icmp eq i32 %fd, 3
  %r = select i1 %ok, i32 0, i32 -1
  ret i32 %r
}

define i32 @open(ptr %p, i32 %f, ...) {
entry:
  ret i32 -1
}

define i32 @creat(ptr %p, i32 %m) {
entry:
  ret i32 -1
}

define i32 @access(ptr %p, i32 %m) {
entry:
  ret i32 -1
}

define i32 @rename(ptr %a, ptr %b) {
entry:
  ret i32 -1
}

define i32 @unlink(ptr %p) {
entry:
  ret i32 -1
}

define ptr @fopen(ptr %p, ptr %m) {
entry:
  ret ptr null
}

define i32 @fileno(ptr %f) {
entry:
  ret i32 -1
}

define i32 @fclose(ptr %f) {
entry:
  ret i32 -1
}

define ptr @opendir(ptr %p) {
entry:
  ret ptr null
}

define i32 @closedir(ptr %d) {
entry:
  ret i32 0
}
