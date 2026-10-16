; host-proc.ll -- the host file for an L0 program run as a process by a
; kernel, at EL0 of an aarch64 machine and in an address space of its own:
; spec section 9.2's process of a kernel. runtime/l0rt.ll calls the
; l0_host_ functions below, spec section 10.3, as on every host; the program
; and l0rt.ll are unchanged. runtime/proc.ld lays out the process, and
; runtime/freestanding.ll, linked beside it, gives the allocator over its
; heap and the mem functions.
;
; It names its architecture's triple, since its entry and its system calls
; are aarch64 instructions, and no board: nothing here is a device's
; address, so one image runs under any kernel that gives what section 10.3
; says a process's host needs.
;
; Everything that leaves the process is a system call (svc #0, the number
; in x8, arguments in x0 to x3, the result in x0), numbered as section 10.3
; fixes them:
;   1  read(stream, buf, n)         6  rename(from, len, to, len)
;   2  write(stream, buf, n)        7  remove(path, len)
;   3  exit(status)                 8  arg_count()
;   4  open(path, len, mode)        9  arg(i, buf, n)
;   5  close(stream)               10  region(base, len)
; What needs no kernel stays here: the allocator, the clock, which reads
; the virtual counter the kernel lets EL0 read, and the barrier. There are
; no settings, as on a host with no environment.
;
; The process's memory, at the virtual addresses proc.ld gives:
;   0xC0000000  the image: code, data, bss, at most 4 MB
;   0xC0400000  the heap, to 0xD8000000
;   0xD8000000  the stack, 256 MB, growing down from 0xE8000000
;   0xE8000000  and above, the kernel's: where it maps regions

target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  bl l0_proc_main"
module asm "1: b 1b"

@__stack_top = external global i8
@__stack_bottom = external global i8

; Defined by runtime/l0rt.ll. Spec section 10.3.
declare i64 @l0_rt_run(i64)

; Defined by runtime/freestanding.ll. A path's length, which the kernel is
; given with it, is strlen's.
declare ptr @l0_host_alloc(i64)
declare i64 @strlen(ptr)

; Called by _start on the stack the kernel gave, from 0xE8000000 down. The
; arguments are fetched first, while nothing is held back to be written, so
; that running out of memory for them can stop the process at once.
; l0_rt_run's frame is a little below the top, so the size it is given
; leaves 64 KB for what lies above it.
define void @l0_proc_main() noreturn {
entry:
  call void @fetch_args()
  %top = ptrtoint ptr @__stack_top to i64
  %bottom = ptrtoint ptr @__stack_bottom to i64
  %all = sub i64 %top, %bottom
  %size = sub i64 %all, 65536
  %st = call i64 @l0_rt_run(i64 %size)
  call void @l0_host_exit(i64 %st)
  unreachable
}

; ------------------------------------------------------------ system calls

define internal i64 @sys(i64 %nr, i64 %a, i64 %b, i64 %c, i64 %d) {
entry:
  %r = call i64 asm sideeffect "svc #0", "={x0},{x0},{x1},{x2},{x3},{x8},~{memory}"(i64 %a, i64 %b, i64 %c, i64 %d, i64 %nr)
  ret i64 %r
}

define i64 @l0_host_read(i64 %s, ptr %buf, i64 %n) {
entry:
  %b = ptrtoint ptr %buf to i64
  %r = call i64 @sys(i64 1, i64 %s, i64 %b, i64 %n, i64 0)
  ret i64 %r
}

define i64 @l0_host_write(i64 %s, ptr %buf, i64 %n) {
entry:
  %b = ptrtoint ptr %buf to i64
  %r = call i64 @sys(i64 2, i64 %s, i64 %b, i64 %n, i64 0)
  ret i64 %r
}

define void @l0_host_exit(i64 %status) noreturn {
entry:
  %r = call i64 @sys(i64 3, i64 %status, i64 0, i64 0, i64 0)
  br label %hang
hang:
  br label %hang
}

define i64 @l0_host_open(ptr %path, i64 %mode) {
entry:
  %p = ptrtoint ptr %path to i64
  %n = call i64 @strlen(ptr %path)
  %r = call i64 @sys(i64 4, i64 %p, i64 %n, i64 %mode, i64 0)
  ret i64 %r
}

define i64 @l0_host_close(i64 %s) {
entry:
  %r = call i64 @sys(i64 5, i64 %s, i64 0, i64 0, i64 0)
  ret i64 %r
}

define i64 @l0_host_rename(ptr %from, ptr %to) {
entry:
  %a = ptrtoint ptr %from to i64
  %an = call i64 @strlen(ptr %from)
  %b = ptrtoint ptr %to to i64
  %bn = call i64 @strlen(ptr %to)
  %r = call i64 @sys(i64 6, i64 %a, i64 %an, i64 %b, i64 %bn)
  ret i64 %r
}

define i64 @l0_host_remove(ptr %path) {
entry:
  %p = ptrtoint ptr %path to i64
  %n = call i64 @strlen(ptr %path)
  %r = call i64 @sys(i64 7, i64 %p, i64 %n, i64 0, i64 0)
  ret i64 %r
}

; One of the kernel's own calls, numbered from 256, spec section 6.15,
; which l0rt.ll has checked.
define i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %b, i64 %c) {
entry:
  %r = call i64 @sys(i64 %n, i64 %a, i64 %b, i64 %c, i64 0)
  ret i64 %r
}

; The address in this process at which the kernel mapped the device, or
; -3 or -5. base and len are checked by l0rt.ll first; the kernel checks
; them again, since it cannot trust a process.
define i64 @l0_host_region(i64 %base, i64 %len) {
entry:
  %r = call i64 @sys(i64 10, i64 %base, i64 %len, i64 0, i64 0)
  ret i64 %r
}

; ------------------------------------------------------------- arguments

; The arguments, asked for once, before the program starts: their count,
; and a table of that many NUL-terminated copies on the heap.
@arg_n = internal global i64 0
@arg_table = internal global ptr null
@empty = private constant [1 x i8] zeroinitializer
@m_heap = private constant [34 x i8] c"l0: runtime error: heap exhausted\0A"

; Spec section 8's heap exhaustion, as l0rt.ll reports it, at a point where
; nothing is held back to deliver first.
define internal void @out_of_memory() noreturn {
entry:
  %w = call i64 @l0_host_write(i64 2, ptr @m_heap, i64 34)
  call void @l0_host_exit(i64 70)
  unreachable
}

define internal void @fetch_args() {
entry:
  %c = call i64 @sys(i64 8, i64 0, i64 0, i64 0, i64 0)
  %some = icmp sgt i64 %c, 0
  br i1 %some, label %table, label %done
table:
  %bytes = mul i64 %c, 8
  %t = call ptr @l0_host_alloc(i64 %bytes)
  %tnull = icmp eq ptr %t, null
  br i1 %tnull, label %oom, label %each
each:
  %i = phi i64 [ 0, %table ], [ %i1, %stored ]
  %len = call i64 @sys(i64 9, i64 %i, i64 0, i64 0, i64 0)
  %gone = icmp slt i64 %len, 0
  br i1 %gone, label %blank, label %copy
blank:
  br label %stored
copy:
  %size = add i64 %len, 1
  %p = call ptr @l0_host_alloc(i64 %size)
  %pnull = icmp eq ptr %p, null
  br i1 %pnull, label %oom, label %fill
fill:
  %pi = ptrtoint ptr %p to i64
  %got = call i64 @sys(i64 9, i64 %i, i64 %pi, i64 %len, i64 0)
  %zp = getelementptr i8, ptr %p, i64 %len
  store i8 0, ptr %zp
  br label %stored
stored:
  %s = phi ptr [ @empty, %blank ], [ %p, %fill ]
  %slot = getelementptr ptr, ptr %t, i64 %i
  store ptr %s, ptr %slot
  %i1 = add i64 %i, 1
  %more = icmp slt i64 %i1, %c
  br i1 %more, label %each, label %keep
keep:
  store ptr %t, ptr @arg_table
  store i64 %c, ptr @arg_n
  br label %done
oom:
  call void @out_of_memory()
  unreachable
done:
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
  %n = load i64, ptr @arg_n
  %lo = icmp sge i64 %i, 0
  %hi = icmp slt i64 %i, %n
  %in = and i1 %lo, %hi
  br i1 %in, label %get, label %none
get:
  %t = load ptr, ptr @arg_table
  %slot = getelementptr ptr, ptr %t, i64 %i
  %s = load ptr, ptr %slot
  ret ptr %s
none:
  ret ptr @empty
}

; ----------------------------------------------- what stays in the process

; No environment, as section 9.2 says of a host without one.
define ptr @l0_host_setting(ptr %name) {
entry:
  ret ptr null
}

; The virtual counter, at cntfrq_el0 counts a second, in seconds and then
; nanoseconds, so that the product cannot overflow; the kernel lets EL0
; read both.
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

define void @l0_host_barrier() {
entry:
  call void asm sideeffect "dsb sy", "~{memory}"()
  ret void
}

; Section 9.2: a process has no user mode of its own, so no space or frame
; is ever made, and anything given one is told 1, not a space, or for a
; frame's address or freeing a frame 2, not a frame.
define i64 @l0_host_space_new() {
entry:
  ret i64 -3
}

define i64 @l0_host_frame_new() {
entry:
  ret i64 -3
}

define i64 @l0_host_frame_address(i64 %f) {
entry:
  ret i64 2
}

define i64 @l0_host_frame_free(i64 %f) {
entry:
  ret i64 2
}

define i64 @l0_host_space_unmap(i64 %s, i64 %va) {
entry:
  ret i64 1
}

define i64 @l0_host_space_free(i64 %s) {
entry:
  ret i64 1
}

define i64 @l0_host_space_map(i64 %s, i64 %va, i64 %f, i64 %perm) {
entry:
  ret i64 1
}

define i64 @l0_host_space_map_device(i64 %s, i64 %va, i64 %base, i64 %len) {
entry:
  ret i64 1
}

define i64 @l0_host_space_copy(i64 %s, i64 %va, ptr %buf, i64 %n, i64 %dir) {
entry:
  ret i64 1
}

define i64 @l0_host_user_run(i64 %s, ptr %words, i64 %n) {
entry:
  ret i64 1
}

; Section 9.2: a process's interrupts are its kernel's, so none is ever
; taken here, and ending one is told 8, interrupt not taken.
define i64 @l0_host_timer_at(i64 %t) {
entry:
  ret i64 -3
}

define i64 @l0_host_interrupt_enable(i64 %n) {
entry:
  ret i64 -3
}

define i64 @l0_host_interrupt_wait() {
entry:
  ret i64 -3
}

define i64 @l0_host_interrupt_done(i64 %n) {
entry:
  ret i64 8
}
