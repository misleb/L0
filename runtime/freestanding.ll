; freestanding.ll -- what a host without libc needs beneath runtime/l0rt.ll,
; spec section 10.3: the allocator, l0_host_alloc, l0_host_alloc_aligned,
; l0_host_resize, and l0_host_free, and memcpy, memmove, memset, memcmp, bcmp, and strlen. It is linked
; beside a host that has no libc, a board's (runtime/bare/board.ll and its
; parts) or a process's (runtime/bare/proc.ll and its CPU's part), and the
; layout that host's linker script gives names the heap, __heap_start to
; __heap_end.
;
; It names no machine, and so carries no target triple, as l0rt.ll does not.

@__heap_start = external global i8
@__heap_end = external global i8

declare i64 @llvm.ctlz.i64(i64, i1)

; ------------------------------------------------------------------ memory
;
; One heap, from __heap_start to __heap_end. A block is a whole number of
; 16-byte units: a header word holding its size with bit 0 set while it is
; in use, a word of padding so that what it holds is 16-byte aligned, as
; malloc's is, then that, and last a footer word repeating the header. A
; free block keeps the next and previous free blocks of its bin in its
; first two words. A used block of 32 bytes at the start and a header of
; size 0 in use at the end bound the heap, so merging never looks past it.
;
; Bin k holds the free blocks whose size has its top bit at k. Allocation
; takes the first block that fits, from the request's bin up, and splits
; off what is left if that makes a block of its own; freeing merges a block
; with a free neighbour on either side, found by the neighbour's header
; above it and footer below it.

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

; The block size that holds n bytes: header, padding, and footer, in whole
; units, and at least 48, room for a free block's two links.
define internal i64 @block_size(i64 %n) {
entry:
  %a = add i64 %n, 39
  %b = and i64 %a, -16
  %small = icmp ult i64 %b, 48
  %r = select i1 %small, i64 48, i64 %b
  ret i64 %r
}

; Marks free block b, of size have, used at size need, freeing what is left
; when it is a block of its own. b is already off its bin.
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

; A block whose contents start at a multiple of align, a power of two: the
; block of n bytes that l0_host_alloc gives, if it is one, and otherwise one
; larger by align and 48 bytes, cut at the first such address at least 48
; bytes in, or at the start, so that what lies before and what lies after
; are blocks of their own, which are then freed and merge as any block does.
; Asked for less than align by 64 bytes or more, blocks taken one after
; another from a free block lie end to end, each where the last left off.
define ptr @l0_host_alloc_aligned(i64 %align, i64 %n) {
entry:
  %huge = icmp ugt i64 %n, 1099511627776
  br i1 %huge, label %none, label %try
try:
  %p0 = call ptr @l0_host_alloc(i64 %n)
  %null0 = icmp eq ptr %p0, null
  br i1 %null0, label %none, label %check
check:
  %p0i = ptrtoint ptr %p0 to i64
  %low = sub i64 %align, 1
  %off = and i64 %p0i, %low
  %fits = icmp eq i64 %off, 0
  br i1 %fits, label %direct, label %undo
direct:
  ret ptr %p0
undo:
  call void @l0_host_free(ptr %p0)
  br label %go
go:
  %extra = add i64 %align, 48
  %want = add i64 %n, %extra
  %p = call ptr @l0_host_alloc(i64 %want)
  %null = icmp eq ptr %p, null
  br i1 %null, label %none, label %got
got:
  %u0 = ptrtoint ptr %p to i64
  %a1 = sub i64 %align, 1
  %r0 = add i64 %u0, %a1
  %na = sub i64 0, %align
  %ua = and i64 %r0, %na
  %g0 = sub i64 %ua, %u0
  %tiny = icmp ult i64 %g0, 48
  %some = icmp ne i64 %g0, 0
  %shift = and i1 %tiny, %some
  %ub = add i64 %ua, %align
  %u = select i1 %shift, i64 %ub, i64 %ua
  %g = sub i64 %u, %u0
  %b0 = sub i64 %u0, 16
  %h0p = inttoptr i64 %b0 to ptr
  %t0 = load i64, ptr %h0p
  %s0 = and i64 %t0, -16
  %b = sub i64 %u, 16
  %need = call i64 @block_size(i64 %n)
  %rest = sub i64 %s0, %g
  %tail = sub i64 %rest, %need
  %cut = icmp uge i64 %tail, 48
  br i1 %cut, label %trim, label %whole
trim:
  call void @set_tags(i64 %b, i64 %need, i64 1)
  %tb = add i64 %b, %need
  call void @set_tags(i64 %tb, i64 %tail, i64 1)
  %tu = add i64 %tb, 16
  %tp = inttoptr i64 %tu to ptr
  call void @l0_host_free(ptr %tp)
  br label %lead
whole:
  call void @set_tags(i64 %b, i64 %rest, i64 1)
  br label %lead
lead:
  br i1 %some, label %front, label %done
front:
  call void @set_tags(i64 %b0, i64 %g, i64 1)
  call void @l0_host_free(ptr %p)
  br label %done
done:
  %r = inttoptr i64 %u to ptr
  ret ptr %r
none:
  ret ptr null
}

; In place when the block already holds n bytes, or can take in the free
; block above it; otherwise moved.
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
;
; memcpy, memmove, memset, and memcmp, which l0rt.ll and LLVM's memory
; intrinsics call (spec section 10.3), and bcmp and strlen, which LLVM may
; make of a memcmp whose result is only compared with 0 and of a loop that
; finds a NUL. Whole words when every
; address and the count allow it, bytes otherwise. "no-builtins" keeps LLVM
; from recognizing their loops as calls to themselves.

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

; What LLVM makes of a loop that looks for a NUL, as l0rt.ll's do for a
; path or an argument, which a host with files or arguments reaches.
define i64 @strlen(ptr %s) #0 {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %step ]
  %p = getelementptr i8, ptr %s, i64 %i
  %c = load i8, ptr %p
  %end = icmp eq i8 %c, 0
  br i1 %end, label %done, label %step
step:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %i
}

attributes #0 = { "no-builtins" }
