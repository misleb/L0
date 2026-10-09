; proc.ll -- 0074's prototype host file for an L0 program run as a process
; at EL0 by kernel.ll, in an address space of its own. runtime/l0rt.ll calls
; the l0_host_ functions below, spec section 10.3, as it does on every host;
; the program and l0rt.ll are unchanged. proc.ld lays out the process.
;
; What the kernel gives, by a system call (svc #0, the number in x8):
;   1  read(stream, buf, n)   as l0_host_read
;   2  write(stream, buf, n)  as l0_host_write
;   3  exit(status)           does not return
; Each l0_host_ function that crosses to the kernel is one call, so this is
; the candidate for "one system call per l0_host_* function, fixed by the
; spec". The clock is read here, from cntvct_el0, which the kernel lets EL0
; read; no files, arguments, or environment, as on the board (section 9.2).
;
; The process's memory, at the addresses proc.ld gives:
;   0xC0000000  the image: code, data, bss
;   0xC0400000  the heap, to 0xD8000000
;   0xD8000000  the stack, 256 MB, growing down from 0xE8000000
; The kernel maps the image when it makes the process, and a 2 MB block of
; the heap or the stack the first time the process touches it.

target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  bl l0_proc_main"
module asm "1: b 1b"

@__stack_top = external global i8
@__stack_bottom = external global i8
@__heap_start = external global i8
@__heap_end = external global i8

declare i64 @l0_rt_run(i64)
declare i64 @llvm.ctlz.i64(i64, i1)

define void @l0_proc_main() noreturn {
entry:
  %top = ptrtoint ptr @__stack_top to i64
  %bottom = ptrtoint ptr @__stack_bottom to i64
  %all = sub i64 %top, %bottom
  %size = sub i64 %all, 65536
  %st = call i64 @l0_rt_run(i64 %size)
  call void @l0_host_exit(i64 %st)
  unreachable
}

; ------------------------------------------------------------ system calls

define internal i64 @sys3(i64 %nr, i64 %a, i64 %b, i64 %c) {
entry:
  %r = call i64 asm sideeffect "svc #0", "={x0},{x0},{x1},{x2},{x8},~{memory}"(i64 %a, i64 %b, i64 %c, i64 %nr)
  ret i64 %r
}

define i64 @l0_host_read(i64 %s, ptr %buf, i64 %n) {
entry:
  %b = ptrtoint ptr %buf to i64
  %r = call i64 @sys3(i64 1, i64 %s, i64 %b, i64 %n)
  ret i64 %r
}

define i64 @l0_host_write(i64 %s, ptr %buf, i64 %n) {
entry:
  %b = ptrtoint ptr %buf to i64
  %r = call i64 @sys3(i64 2, i64 %s, i64 %b, i64 %n)
  ret i64 %r
}

define void @l0_host_exit(i64 %status) noreturn {
entry:
  %r = call i64 @sys3(i64 3, i64 %status, i64 0, i64 0)
  br label %hang
hang:
  br label %hang
}

define i64 @l0_host_close(i64 %s) {
entry:
  ret i64 -5
}

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

; No device is mapped into a process yet, so no region (spec section 6.12).
define i64 @l0_host_region(i64 %base, i64 %len) {
entry:
  ret i64 -3
}

define void @l0_host_barrier() {
entry:
  call void asm sideeffect "dsb sy", "~{memory}"()
  ret void
}

; ------------------------------------------------------------------ memory
;
; runtime/host-virt.ll's allocator, unchanged, over this process's heap.

@heap_ready = internal global i1 false
@bins = internal global [64 x i64] zeroinitializer

define internal i64 @bin_of(i64 %size) {
entry:
  %z = call i64 @llvm.ctlz.i64(i64 %size, i1 true)
  %k = sub i64 63, %z
  ret i64 %k
}

define internal void @set_tags(i64 %b, i64 %size, i64 %used) {
entry:
  %tag = or i64 %size, %used
  %hp = inttoptr i64 %b to ptr
  store i64 %tag, ptr %hp
  %f = add i64 %b, %size
  %f8 = sub i64 %f, 8
  %fp = inttoptr i64 %f8 to ptr
  store i64 %tag, ptr %fp
  ret void
}

define internal void @bin_insert(i64 %b) {
entry:
  %hp = inttoptr i64 %b to ptr
  %size = load i64, ptr %hp
  %k = call i64 @bin_of(i64 %size)
  %bp = getelementptr [64 x i64], ptr @bins, i64 0, i64 %k
  %next = load i64, ptr %bp
  %nxp = getelementptr i8, ptr %hp, i64 16
  store i64 %next, ptr %nxp
  %pvp = getelementptr i8, ptr %hp, i64 24
  store i64 0, ptr %pvp
  %has = icmp ne i64 %next, 0
  br i1 %has, label %link, label %head
link:
  %nq = inttoptr i64 %next to ptr
  %npv = getelementptr i8, ptr %nq, i64 24
  store i64 %b, ptr %npv
  br label %head
head:
  store i64 %b, ptr %bp
  ret void
}

define internal void @bin_remove(i64 %b) {
entry:
  %hp = inttoptr i64 %b to ptr
  %tag = load i64, ptr %hp
  %size = and i64 %tag, -16
  %nxp = getelementptr i8, ptr %hp, i64 16
  %next = load i64, ptr %nxp
  %pvp = getelementptr i8, ptr %hp, i64 24
  %prev = load i64, ptr %pvp
  %first = icmp eq i64 %prev, 0
  br i1 %first, label %head, label %mid
head:
  %k = call i64 @bin_of(i64 %size)
  %bp = getelementptr [64 x i64], ptr @bins, i64 0, i64 %k
  store i64 %next, ptr %bp
  br label %after
mid:
  %pq = inttoptr i64 %prev to ptr
  %pnx = getelementptr i8, ptr %pq, i64 16
  store i64 %next, ptr %pnx
  br label %after
after:
  %has = icmp ne i64 %next, 0
  br i1 %has, label %back, label %done
back:
  %nq = inttoptr i64 %next to ptr
  %npv = getelementptr i8, ptr %nq, i64 24
  store i64 %prev, ptr %npv
  br label %done
done:
  ret void
}

define internal void @heap_init() {
entry:
  %s0 = ptrtoint ptr @__heap_start to i64
  %s1 = add i64 %s0, 15
  %start = and i64 %s1, -16
  %e0 = ptrtoint ptr @__heap_end to i64
  %end = and i64 %e0, -16
  call void @set_tags(i64 %start, i64 32, i64 1)
  %first = add i64 %start, 32
  %last = sub i64 %end, 16
  %size = sub i64 %last, %first
  call void @set_tags(i64 %first, i64 %size, i64 0)
  call void @bin_insert(i64 %first)
  %ep = inttoptr i64 %last to ptr
  store i64 1, ptr %ep
  store i1 true, ptr @heap_ready
  ret void
}

define internal i64 @block_size(i64 %n) {
entry:
  %a = add i64 %n, 39
  %b = and i64 %a, -16
  %small = icmp ult i64 %b, 48
  %r = select i1 %small, i64 48, i64 %b
  ret i64 %r
}

define internal void @take(i64 %b, i64 %have, i64 %need) {
entry:
  %left = sub i64 %have, %need
  %split = icmp uge i64 %left, 48
  br i1 %split, label %cut, label %whole
cut:
  call void @set_tags(i64 %b, i64 %need, i64 1)
  %r = add i64 %b, %need
  call void @set_tags(i64 %r, i64 %left, i64 0)
  call void @bin_insert(i64 %r)
  ret void
whole:
  call void @set_tags(i64 %b, i64 %have, i64 1)
  ret void
}

define ptr @l0_host_alloc(i64 %n) {
entry:
  %ready = load i1, ptr @heap_ready
  br i1 %ready, label %sized, label %init
init:
  call void @heap_init()
  br label %sized
sized:
  %huge = icmp ugt i64 %n, 1099511627776
  br i1 %huge, label %none, label %go
go:
  %need = call i64 @block_size(i64 %n)
  %k0 = call i64 @bin_of(i64 %need)
  br label %bin
bin:
  %k = phi i64 [ %k0, %go ], [ %k1, %empty ]
  %out = icmp eq i64 %k, 64
  br i1 %out, label %none, label %scan0
scan0:
  %bp = getelementptr [64 x i64], ptr @bins, i64 0, i64 %k
  %h0 = load i64, ptr %bp
  br label %scan
scan:
  %b = phi i64 [ %h0, %scan0 ], [ %nb, %next ]
  %end = icmp eq i64 %b, 0
  br i1 %end, label %empty, label %look
look:
  %hp = inttoptr i64 %b to ptr
  %size = load i64, ptr %hp
  %fits = icmp uge i64 %size, %need
  br i1 %fits, label %found, label %next
next:
  %nxp = getelementptr i8, ptr %hp, i64 16
  %nb = load i64, ptr %nxp
  br label %scan
empty:
  %k1 = add i64 %k, 1
  br label %bin
found:
  call void @bin_remove(i64 %b)
  call void @take(i64 %b, i64 %size, i64 %need)
  %u = getelementptr i8, ptr %hp, i64 16
  ret ptr %u
none:
  ret ptr null
}

define void @l0_host_free(ptr %p) {
entry:
  %null = icmp eq ptr %p, null
  br i1 %null, label %done, label %go
go:
  %pi = ptrtoint ptr %p to i64
  %b0 = sub i64 %pi, 16
  %h0p = inttoptr i64 %b0 to ptr
  %t0 = load i64, ptr %h0p
  %s0 = and i64 %t0, -16
  %nb = add i64 %b0, %s0
  %nhp = inttoptr i64 %nb to ptr
  %nt = load i64, ptr %nhp
  %nused = and i64 %nt, 1
  %nfree = icmp eq i64 %nused, 0
  br i1 %nfree, label %merge_next, label %below
merge_next:
  call void @bin_remove(i64 %nb)
  %s1a = add i64 %s0, %nt
  br label %below
below:
  %s1 = phi i64 [ %s0, %go ], [ %s1a, %merge_next ]
  %pfa = sub i64 %b0, 8
  %pfp = inttoptr i64 %pfa to ptr
  %pt = load i64, ptr %pfp
  %pused = and i64 %pt, 1
  %pfree = icmp eq i64 %pused, 0
  br i1 %pfree, label %merge_prev, label %put
merge_prev:
  %pb = sub i64 %b0, %pt
  call void @bin_remove(i64 %pb)
  %s2a = add i64 %s1, %pt
  br label %put
put:
  %b = phi i64 [ %b0, %below ], [ %pb, %merge_prev ]
  %s = phi i64 [ %s1, %below ], [ %s2a, %merge_prev ]
  call void @set_tags(i64 %b, i64 %s, i64 0)
  call void @bin_insert(i64 %b)
  br label %done
done:
  ret void
}

define ptr @l0_host_resize(ptr %p, i64 %n) {
entry:
  %null = icmp eq ptr %p, null
  br i1 %null, label %fresh, label %have
fresh:
  %f = call ptr @l0_host_alloc(i64 %n)
  ret ptr %f
have:
  %huge = icmp ugt i64 %n, 1099511627776
  br i1 %huge, label %fail, label %sized
sized:
  %pi = ptrtoint ptr %p to i64
  %b = sub i64 %pi, 16
  %hp = inttoptr i64 %b to ptr
  %t = load i64, ptr %hp
  %s = and i64 %t, -16
  %cap = sub i64 %s, 24
  %fits = icmp ule i64 %n, %cap
  br i1 %fits, label %same, label %grow
same:
  ret ptr %p
grow:
  %need = call i64 @block_size(i64 %n)
  %nb = add i64 %b, %s
  %nhp = inttoptr i64 %nb to ptr
  %nt = load i64, ptr %nhp
  %nused = and i64 %nt, 1
  %nfree = icmp eq i64 %nused, 0
  %both = add i64 %s, %nt
  %room = icmp uge i64 %both, %need
  %absorb = and i1 %nfree, %room
  br i1 %absorb, label %extend, label %move
extend:
  call void @bin_remove(i64 %nb)
  call void @take(i64 %b, i64 %both, i64 %need)
  ret ptr %p
move:
  %q = call ptr @l0_host_alloc(i64 %n)
  %failed = icmp eq ptr %q, null
  br i1 %failed, label %fail, label %copy
copy:
  %x = call ptr @memcpy(ptr %q, ptr %p, i64 %cap)
  call void @l0_host_free(ptr %p)
  ret ptr %q
fail:
  ret ptr null
}

; --------------------------------------------- what a C environment provides

define ptr @memcpy(ptr %d, ptr %s, i64 %n) #0 {
entry:
  %di = ptrtoint ptr %d to i64
  %si = ptrtoint ptr %s to i64
  %a = or i64 %di, %si
  %b = or i64 %a, %n
  %odd = and i64 %b, 7
  %bytes = icmp ne i64 %odd, 0
  br i1 %bytes, label %bloop, label %wloop
wloop:
  %i = phi i64 [ 0, %entry ], [ %i1, %wbody ]
  %wmore = icmp ult i64 %i, %n
  br i1 %wmore, label %wbody, label %done
wbody:
  %sp = getelementptr i8, ptr %s, i64 %i
  %w = load i64, ptr %sp
  %dp = getelementptr i8, ptr %d, i64 %i
  store i64 %w, ptr %dp
  %i1 = add i64 %i, 8
  br label %wloop
bloop:
  %j = phi i64 [ 0, %entry ], [ %j1, %bbody ]
  %bmore = icmp ult i64 %j, %n
  br i1 %bmore, label %bbody, label %done
bbody:
  %sq = getelementptr i8, ptr %s, i64 %j
  %c = load i8, ptr %sq
  %dq = getelementptr i8, ptr %d, i64 %j
  store i8 %c, ptr %dq
  %j1 = add i64 %j, 1
  br label %bloop
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
