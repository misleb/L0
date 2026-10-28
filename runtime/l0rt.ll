; l0rt.ll -- the runtime linked into every compiled L0 program. Spec section
; 10.3 is its interface; section 9 is the host half of the contract it
; implements, for either form of main; section 6.2 is what read_byte and
; write_byte promise.
;
; It carries no target triple, and is the same text on every host. It
; reaches the host only through the l0_host_ functions of spec section 10.3,
; which a host defines: runtime/host-libc.ll on macOS and Linux, and the
; parts of runtime/bare/ and those beside them without libc. Beyond
; those it calls only memcmp, as every C environment provides, and LLVM's
; memory intrinsics. A host file's results are already spec section 6.3's
; codes, so nothing here knows how a host tells its failures apart.

declare ptr @l0_host_alloc(i64)
declare ptr @l0_host_alloc_aligned(i64, i64)
declare ptr @l0_host_resize(ptr, i64)
declare void @l0_host_free(ptr)
declare i64 @l0_host_read(i64, ptr, i64)
declare i64 @l0_host_write(i64, ptr, i64)
declare i64 @l0_host_open(ptr, i64)
declare i64 @l0_host_close(i64)
declare i64 @l0_host_rename(ptr, ptr)
declare i64 @l0_host_remove(ptr)
declare i64 @l0_host_clock_ns()
declare i64 @l0_host_machine()
declare i64 @l0_host_board_reset()
declare i64 @l0_host_arg_count()
declare ptr @l0_host_arg(i64)
declare ptr @l0_host_setting(ptr)
declare void @l0_host_exit(i64) noreturn
declare i64 @l0_host_region(i64, i64)
declare void @l0_host_region_close(i64, i64)
declare void @l0_host_barrier()
declare i64 @l0_host_space_new()
declare i64 @l0_host_frame_new()
declare i64 @l0_host_frame_address(i64)
declare i64 @l0_host_frame_sync(i64, i64)
declare i64 @l0_host_space_map(i64, i64, i64, i64)
declare i64 @l0_host_space_map_device(i64, i64, i64, i64)
declare i64 @l0_host_space_unmap(i64, i64)
declare i64 @l0_host_space_free(i64)
declare i64 @l0_host_frame_free(i64)
declare i64 @l0_host_frame_free_count()
declare i64 @l0_host_space_copy(i64, i64, ptr, i64, i64)
declare i64 @l0_host_user_run(i64, ptr, i64)
declare i64 @l0_host_timer_at(i64)
declare i64 @l0_host_interrupt_enable(i64)
declare i64 @l0_host_interrupt_wait()
declare i64 @l0_host_interrupt_done(i64)
declare i64 @l0_host_supervisor(i64, i64, i64, i64)
declare i64 @l0_host_cpu_count()
declare i64 @l0_host_cpu_run(i64, i64, ptr, i64, i64, i64)
declare i64 @l0_host_cpu_trapped(ptr)
declare i64 @l0_host_cpu_wait()
declare i64 @l0_host_heap_left()
declare ptr @llvm.frameaddress.p0(i32)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)
declare i64 @llvm.ctpop.i64(i64)
declare i32 @memcmp(ptr, ptr, i64)

; Defined by the generated IR. Spec section 10.2.
declare i64 @l0_f_main(i64)
@l0_main_ret_kind = external global i64

@stack_limit = internal global i64 0

; The handle table of spec section 6.3. A handle is an index into it. mode is
; 0 for closed, 1 for reading, and 2 for writing; state is 0 when all is well,
; 1 once end of input is seen, 2 after a read failed, 3 after a write failed
; that no flush or close has reported, and 4 once one has. Every state but 0
; sticks, so a terminal is not asked for a second end of file, and a lost
; byte is never forgotten; a new write failure turns 4 back into 3.
; For reading, pos and len delimit the unread bytes in buf; for writing, len
; is how many bytes are held back. Handles 0, 1, and 2 use the static buffers
; below and are never closed; the rest get a buffer from malloc when opened.
;
; kind is 0 for a descriptor, 1 for a handle reading a list, and 2 for a
; buffer, spec section 6.3. A list handle has no fd or buf: list is the list
; it holds a reference to, and pos the cell to read next, 0 at the end. A
; buffer has no fd: buf holds everything written, len bytes of cap.
@h_kind = internal global [64 x i64] zeroinitializer
@h_list = internal global [64 x i64] zeroinitializer
@h_cap = internal global [64 x i64] zeroinitializer
@h_fd = internal global [64 x i64] zeroinitializer
@h_mode = internal global [64 x i64] zeroinitializer
@h_state = internal global [64 x i64] zeroinitializer
; For a writing handle in state 3 or 4, the spec section 6.3 code of the first
; byte lost: -5, -6, or -7. 0 until one is.
@h_err = internal global [64 x i64] zeroinitializer
@h_buf = internal global [64 x ptr] zeroinitializer
@h_pos = internal global [64 x i64] zeroinitializer
@h_len = internal global [64 x i64] zeroinitializer
@in_buf = internal global [65536 x i8] zeroinitializer
@out_buf = internal global [65536 x i8] zeroinitializer
@err_buf = internal global [65536 x i8] zeroinitializer

@pfx = private constant [19 x i8] c"l0: runtime error: "
@nl = private constant [1 x i8] c"\0A"
@m_heap = private constant [14 x i8] c"heap exhausted"
@m_head = private constant [18 x i8] c"head of empty list"
@m_tail = private constant [18 x i8] c"tail of empty list"
@m_div = private constant [16 x i8] c"division by zero"
@m_mod = private constant [14 x i8] c"modulo by zero"
@m_stack = private constant [15 x i8] c"stack exhausted"
@m_write = private constant [12 x i8] c"write failed"
@s_true = private constant [5 x i8] c"true\0A"
@s_false = private constant [6 x i8] c"false\0A"
@check_name = private constant [12 x i8] c"L0_RC_CHECK\00"
@m_uaf = private constant [20 x i8] c"use of a freed block"
@m_live = private constant [23 x i8] c"l0: blocks still live: "
@m_range = private constant [24 x i8] c"array index out of range"
@m_alen = private constant [21 x i8] c"negative array length"
@m_shift = private constant [14 x i8] c"negative shift"
@stats_name = private constant [15 x i8] c"L0_ARRAY_STATS\00"
@m_copies = private constant [18 x i8] c"l0: array copies: "
@m_inplace = private constant [25 x i8] c"l0: array sets in place: "
@m_words = private constant [24 x i8] c"l0: array words copied: "
; ------------------------------------------------------------------ errors

; Returns 0 if every byte was written, or the spec section 6.3 code of the
; write that failed: -5, -6, or -7.
define internal i64 @write_all_rc(i32 %fd, ptr %p, i64 %n) {
entry:
  %s = sext i32 %fd to i64
  br label %loop
loop:
  %cp = phi ptr [ %p, %entry ], [ %np, %more ]
  %cn = phi i64 [ %n, %entry ], [ %nn, %more ]
  %done = icmp sle i64 %cn, 0
  br i1 %done, label %ok, label %body
body:
  %w = call i64 @l0_host_write(i64 %s, ptr %cp, i64 %cn)
  %bad = icmp slt i64 %w, 0
  br i1 %bad, label %fail, label %more
more:
  %np = getelementptr i8, ptr %cp, i64 %w
  %nn = sub i64 %cn, %w
  br label %loop
ok:
  ret i64 0
fail:
  ret i64 %w
}

define internal void @write_all(i32 %fd, ptr %p, i64 %n) {
entry:
  %r = call i64 @write_all_rc(i32 %fd, ptr %p, i64 %n)
  ret void
}

; As write_all, for output that is the program's own, such as main's result:
; a failure is recorded against the handle of the same number, unreported,
; so that the exit check of spec section 6.3 sees it. fd is 1 or 2.
define internal void @write_mark(i32 %fd, ptr %p, i64 %n) {
entry:
  %r = call i64 @write_all_rc(i32 %fd, ptr %p, i64 %n)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %mark, label %done
mark:
  %h = sext i32 %fd to i64
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  store i64 3, ptr %sp
  br label %done
done:
  ret void
}

; Bytes the program wrote, to any handle, are delivered before the
; diagnostic, and a main that takes its input never has its result written,
; as spec section 8 requires.
define internal void @rt_error(ptr %m, i64 %n) noreturn noinline {
entry:
  call void @flush_every()
  call void @write_all(i32 2, ptr @pfx, i64 19)
  call void @write_all(i32 2, ptr %m, i64 %n)
  call void @write_all(i32 2, ptr @nl, i64 1)
  call void @l0_host_exit(i64 70)
  unreachable
}

; ------------------------------------------------------------------ chunks
;
; Cons cells and data blocks are cut from chunks of 1 MiB less 64 bytes,
; aligned to 1 MiB, so a block's chunk is its address with the low 20 bits
; cleared; the 64 bytes are what a host's allocator may keep beside a
; block, so that chunks it gives one after another can lie end to end. The
; current chunk is cut from its start up, every block a whole number of
; words, and a chunk starts with four words:
;
;   0  scratch for a sweep: the bytes of its blocks on free lists, or -1
;      once the sweep has taken it
;   1  how far it was cut, in bytes, from the end of these words
;   2  the next chunk in use, from @chunks
;   3  the next chunk, among the empty chunks or those a sweep took
;
; A freed block goes on the free list for its size, threaded through its
; header word, which allocation takes from before the current chunk, so
; taking and giving a block touch only that list, the block, and
; @free_bytes, the bytes on all the lists, which heap_left reads. Nothing
; else counts as blocks come and go. A sweep counts instead: it adds up, chunk by
; chunk, the bytes on the free lists, and a chunk other than the current one
; whose count is how far it was cut has every block free. It takes those
; blocks off their lists and gives those chunks back. A sweep walks every
; free list, so one runs only as a new chunk is made, once the chunks made
; since the last are a quarter of all there are and at least one: a sweep
; walks no more blocks than the chunks hold, so sweeping costs a bounded
; share of cutting them. Arrays and bytes, which come from the host, do not
; count, since a program may take far more that way than it ever holds in
; chunks. One runs too whenever the host has no memory for an allocation,
; before it is asked again. A chunk given back goes on the empty chunks,
; which a new chunk is taken from before the host, and to the host once 4
; are kept. Spec section 10.3.

@free_lists = internal global [257 x i64] zeroinitializer
@free_bytes = internal global i64 0
@chunk = internal global i64 0
@chunk_cur = internal global i64 0
@chunk_end = internal global i64 0
@chunks = internal global i64 0
@chunk_count = internal global i64 0
@made_since = internal global i64 0
@empty_chunks = internal global i64 0
@empty_count = internal global i64 0

; Counts n bytes of chunks about to be made, and sweeps first if that makes
; a sweep due.
define internal void @making(i64 %n) {
entry:
  %s = load i64, ptr @made_since
  %s1 = add i64 %s, %n
  store i64 %s1, ptr @made_since
  %k = load i64, ptr @chunk_count
  %quarter = shl i64 %k, 18
  %least = icmp ult i64 %quarter, 1048576
  %bar = select i1 %least, i64 1048576, i64 %quarter
  %due = icmp uge i64 %s1, %bar
  br i1 %due, label %sweep, label %done
sweep:
  call void @sweep(i1 false)
  br label %done
done:
  ret void
}

; l0_host_alloc and l0_host_resize, but when the host has no memory, asked
; again after a sweep gives back the chunks it can.
define internal ptr @host_alloc(i64 %n) {
entry:
  %p = call ptr @l0_host_alloc(i64 %n)
  %null = icmp eq ptr %p, null
  br i1 %null, label %again, label %done
again:
  call void @sweep(i1 true)
  %q = call ptr @l0_host_alloc(i64 %n)
  ret ptr %q
done:
  ret ptr %p
}

define internal ptr @host_resize(ptr %old, i64 %n) {
entry:
  %p = call ptr @l0_host_resize(ptr %old, i64 %n)
  %null = icmp eq ptr %p, null
  br i1 %null, label %again, label %done
again:
  call void @sweep(i1 true)
  %q = call ptr @l0_host_resize(ptr %old, i64 %n)
  ret ptr %q
done:
  ret ptr %p
}

; Puts chunk c among the empty chunks, or gives it to the host when 4 are.
define internal void @chunk_drop(i64 %c) {
entry:
  %cq = inttoptr i64 %c to ptr
  %n = load i64, ptr @empty_count
  %many = icmp uge i64 %n, 4
  br i1 %many, label %give, label %keep
keep:
  %e = load i64, ptr @empty_chunks
  %np = getelementptr i64, ptr %cq, i64 3
  store i64 %e, ptr %np
  store i64 %c, ptr @empty_chunks
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @empty_count
  ret void
give:
  call void @l0_host_free(ptr %cq)
  ret void
}

; Makes a new chunk current, cutting a block of b bytes from its start, and
; returns that block: one of the empty chunks, or a new one from the host.
; The chunk it replaces records how far it was cut, and a sweep may run
; first, which that chunk is then open to.
define internal i64 @chunk_new(i64 %b) noinline {
entry:
  %c0 = load i64, ptr @chunk
  %had = icmp ne i64 %c0, 0
  br i1 %had, label %retire, label %decide
retire:
  %cur = load i64, ptr @chunk_cur
  %start0 = add i64 %c0, 32
  %ext = sub i64 %cur, %start0
  %c0q = inttoptr i64 %c0 to ptr
  %xp = getelementptr i64, ptr %c0q, i64 1
  store i64 %ext, ptr %xp
  store i64 0, ptr @chunk
  store i64 0, ptr @chunk_cur
  store i64 0, ptr @chunk_end
  br label %decide
decide:
  call void @making(i64 1048576)
  br label %get
get:
  %swept = phi i1 [ false, %decide ], [ true, %retry ]
  %e = load i64, ptr @empty_chunks
  %have = icmp ne i64 %e, 0
  br i1 %have, label %reuse, label %fresh
reuse:
  %eq = inttoptr i64 %e to ptr
  %enp = getelementptr i64, ptr %eq, i64 3
  %next = load i64, ptr %enp
  store i64 %next, ptr @empty_chunks
  %n = load i64, ptr @empty_count
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr @empty_count
  br label %init
fresh:
  %m = call ptr @l0_host_alloc_aligned(i64 1048576, i64 1048512)
  %null = icmp eq ptr %m, null
  br i1 %null, label %none, label %got
none:
  br i1 %swept, label %oom, label %retry
retry:
  call void @sweep(i1 true)
  br label %get
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
got:
  %mi = ptrtoint ptr %m to i64
  br label %init
init:
  %c = phi i64 [ %e, %reuse ], [ %mi, %got ]
  %cq = inttoptr i64 %c to ptr
  %lp = getelementptr i64, ptr %cq, i64 2
  %head = load i64, ptr @chunks
  store i64 %head, ptr %lp
  store i64 %c, ptr @chunks
  %k = load i64, ptr @chunk_count
  %k1 = add i64 %k, 1
  store i64 %k1, ptr @chunk_count
  store i64 %c, ptr @chunk
  %blk = add i64 %c, 32
  %after = add i64 %blk, %b
  store i64 %after, ptr @chunk_cur
  %end = add i64 %c, 1048512
  store i64 %end, ptr @chunk_end
  ret i64 %blk
}

; Gives back every chunk, other than the current one, whose blocks are all
; on free lists, taking those blocks off the lists and keeping the order of
; the rest. When the host has no memory, urgent is true, and nothing is held
; back: the current chunk is no longer current, so it is given back too if
; it can be, and the empty chunks kept go back to the host.
define internal void @sweep(i1 %urgent) noinline {
entry:
  %cur0 = load i64, ptr @chunk
  %has = icmp ne i64 %cur0, 0
  br i1 %has, label %mark, label %marked
mark:
  %cc = load i64, ptr @chunk_cur
  %start = add i64 %cur0, 32
  %ext = sub i64 %cc, %start
  %curq = inttoptr i64 %cur0 to ptr
  %xp = getelementptr i64, ptr %curq, i64 1
  store i64 %ext, ptr %xp
  br i1 %urgent, label %retire, label %marked
retire:
  store i64 0, ptr @chunk
  store i64 0, ptr @chunk_cur
  store i64 0, ptr @chunk_end
  br label %marked
marked:
  %cur = load i64, ptr @chunk
  br label %zero
zero:
  %first = load i64, ptr @chunks
  br label %zloop
zloop:
  %z = phi i64 [ %first, %zero ], [ %zn, %zstep ]
  %zend = icmp eq i64 %z, 0
  br i1 %zend, label %count, label %zstep
zstep:
  %zq = inttoptr i64 %z to ptr
  store i64 0, ptr %zq
  %znp = getelementptr i64, ptr %zq, i64 2
  %zn = load i64, ptr %znp
  br label %zloop
count:
  br label %csize
csize:
  %t = phi i64 [ 1, %count ], [ %t1, %cnext ]
  %cdone = icmp ugt i64 %t, 256
  br i1 %cdone, label %pick, label %clist
clist:
  %flp = getelementptr [257 x i64], ptr @free_lists, i64 0, i64 %t
  %top = load i64, ptr %flp
  %b = mul i64 %t, 8
  br label %cwalk
cwalk:
  %k = phi i64 [ %top, %clist ], [ %kn, %cstep ]
  %kend = icmp eq i64 %k, 0
  br i1 %kend, label %cnext, label %cstep
cstep:
  %kq = inttoptr i64 %k to ptr
  %kn = load i64, ptr %kq
  %kc = and i64 %k, -1048576
  %kcq = inttoptr i64 %kc to ptr
  %tally = load i64, ptr %kcq
  %tally1 = add i64 %tally, %b
  store i64 %tally1, ptr %kcq
  br label %cwalk
cnext:
  %t1 = add i64 %t, 1
  br label %csize
pick:
  %slot0 = ptrtoint ptr @chunks to i64
  br label %ploop
ploop:
  %c = phi i64 [ %first, %pick ], [ %cn, %pkeep ], [ %cn, %ptake ]
  %slot = phi i64 [ %slot0, %pick ], [ %cslot, %pkeep ], [ %slot, %ptake ]
  %taken = phi i64 [ 0, %pick ], [ %taken, %pkeep ], [ %c, %ptake ]
  %pend = icmp eq i64 %c, 0
  br i1 %pend, label %picked, label %plook
plook:
  %cq = inttoptr i64 %c to ptr
  %cslotp = getelementptr i64, ptr %cq, i64 2
  %cslot = ptrtoint ptr %cslotp to i64
  %cn = load i64, ptr %cslotp
  %ctally = load i64, ptr %cq
  %cxp = getelementptr i64, ptr %cq, i64 1
  %cext = load i64, ptr %cxp
  %all = icmp eq i64 %ctally, %cext
  %current = icmp eq i64 %c, %cur
  %notcur = xor i1 %current, true
  %idle = and i1 %all, %notcur
  br i1 %idle, label %ptake, label %pkeep
pkeep:
  br label %ploop
ptake:
  store i64 -1, ptr %cq
  %fb = load i64, ptr @free_bytes
  %fb1 = sub i64 %fb, %cext
  store i64 %fb1, ptr @free_bytes
  %sq = inttoptr i64 %slot to ptr
  store i64 %cn, ptr %sq
  %tnp = getelementptr i64, ptr %cq, i64 3
  store i64 %taken, ptr %tnp
  %n = load i64, ptr @chunk_count
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr @chunk_count
  br label %ploop
picked:
  store i64 0, ptr @made_since
  %any = icmp ne i64 %taken, 0
  br i1 %any, label %fsize, label %flush
fsize:
  %u = phi i64 [ 1, %picked ], [ %u1, %fclose ]
  %fdone = icmp ugt i64 %u, 256
  br i1 %fdone, label %give, label %flist
flist:
  %glp = getelementptr [257 x i64], ptr @free_lists, i64 0, i64 %u
  %gtop = load i64, ptr %glp
  %gslot0 = ptrtoint ptr %glp to i64
  br label %fwalk
fwalk:
  %f = phi i64 [ %gtop, %flist ], [ %fn, %fkeep ], [ %fn, %fdrop ]
  %fslot = phi i64 [ %gslot0, %flist ], [ %f, %fkeep ], [ %fslot, %fdrop ]
  %fend = icmp eq i64 %f, 0
  br i1 %fend, label %fclose, label %flook
flook:
  %fq = inttoptr i64 %f to ptr
  %fn = load i64, ptr %fq
  %fc = and i64 %f, -1048576
  %fcq = inttoptr i64 %fc to ptr
  %ft = load i64, ptr %fcq
  %gone = icmp slt i64 %ft, 0
  br i1 %gone, label %fdrop, label %fkeep
fkeep:
  %fsq = inttoptr i64 %fslot to ptr
  store i64 %f, ptr %fsq
  br label %fwalk
fdrop:
  br label %fwalk
fclose:
  %fendq = inttoptr i64 %fslot to ptr
  store i64 0, ptr %fendq
  %u1 = add i64 %u, 1
  br label %fsize
give:
  %r = phi i64 [ %taken, %fsize ], [ %rn, %gmore ]
  %gfin = icmp eq i64 %r, 0
  br i1 %gfin, label %flush, label %gmore
gmore:
  %rq = inttoptr i64 %r to ptr
  %rnp = getelementptr i64, ptr %rq, i64 3
  %rn = load i64, ptr %rnp
  call void @chunk_drop(i64 %r)
  br label %give
flush:
  br i1 %urgent, label %eloop, label %done
eloop:
  %e = load i64, ptr @empty_chunks
  %eend = icmp eq i64 %e, 0
  br i1 %eend, label %emptied, label %estep
estep:
  %eq = inttoptr i64 %e to ptr
  %enp = getelementptr i64, ptr %eq, i64 3
  %en = load i64, ptr %enp
  store i64 %en, ptr @empty_chunks
  call void @l0_host_free(ptr %eq)
  br label %eloop
emptied:
  store i64 0, ptr @empty_count
  br label %done
done:
  ret void
}

; ------------------------------------------------------------------ blocks

; Every block has one header word in front of it, so a value still points at
; its first word and the offsets of spec section 10.1 hold:
;
;   bits  0-31   which of the block's words are pointers, bit k for word k
;   bits 32-39   the block's size in words, not counting the header
;   bits 40-63   the reference count
;
; A count of all ones means the block is never freed; the allocation calls
; that predate counting make blocks like that, so programs an older compiler
; built stay correct. A freed block goes back to its page, above.

; L0_RC_CHECK set in the environment turns on checking: counted blocks are
; counted as they are made and freed, and any left at a normal exit are
; reported; a freed block is poisoned and never reused, so using it again is
; caught rather than hidden by a new occupant.
@rc_check = internal global i64 0
@live = internal global i64 0

; Blocks waiting to be freed, so freeing a long list needs no recursion.
@wl = internal global ptr null
@wl_len = internal global i64 0
@wl_cap = internal global i64 0

define internal i64 @blk_alloc(i64 %words, i64 %mask, i64 %rc) {
entry:
  %counted = icmp eq i64 %rc, 1
  br i1 %counted, label %count, label %sized
count:
  %lv = load i64, ptr @live
  %lv1 = add i64 %lv, 1
  store i64 %lv1, ptr @live
  br label %sized
sized:
  %total = add i64 %words, 1
  %bytes = mul i64 %total, 8
  %flp = getelementptr [257 x i64], ptr @free_lists, i64 0, i64 %total
  %top = load i64, ptr %flp
  %none = icmp eq i64 %top, 0
  br i1 %none, label %cut, label %reuse
reuse:
  %tq = inttoptr i64 %top to ptr
  %next = load i64, ptr %tq
  store i64 %next, ptr %flp
  %fb = load i64, ptr @free_bytes
  %fb1 = sub i64 %fb, %bytes
  store i64 %fb1, ptr @free_bytes
  br label %init
cut:
  %cur = load i64, ptr @chunk_cur
  %end = load i64, ptr @chunk_end
  %after = add i64 %cur, %bytes
  %fits = icmp ule i64 %after, %end
  br i1 %fits, label %bump, label %new
bump:
  store i64 %after, ptr @chunk_cur
  br label %init
new:
  %fresh = call i64 @chunk_new(i64 %bytes)
  br label %init
init:
  %blk = phi i64 [ %top, %reuse ], [ %cur, %bump ], [ %fresh, %new ]
  %hq = inttoptr i64 %blk to ptr
  %rcs = shl i64 %rc, 40
  %ws = shl i64 %words, 32
  %h1 = or i64 %rcs, %ws
  %hdr = or i64 %h1, %mask
  store i64 %hdr, ptr %hq
  %p = add i64 %blk, 8
  ret i64 %p
}

define internal i64 @cons_with(i64 %h, i64 %t, i64 %mask, i64 %rc) {
entry:
  %p = call i64 @blk_alloc(i64 2, i64 %mask, i64 %rc)
  %q = inttoptr i64 %p to ptr
  store i64 %h, ptr %q
  %q1 = getelementptr i64, ptr %q, i64 1
  store i64 %t, ptr %q1
  ret i64 %p
}

define internal i64 @data_with(i64 %tag, i64 %n, i64 %mask, i64 %rc) {
entry:
  %n1 = add i64 %n, 1
  %p = call i64 @blk_alloc(i64 %n1, i64 %mask, i64 %rc)
  %q = inttoptr i64 %p to ptr
  %bytes = mul i64 %n1, 8
  call void @llvm.memset.p0.i64(ptr %q, i8 0, i64 %bytes, i1 false)
  store i64 %tag, ptr %q
  ret i64 %p
}

; ---------------------------------------------------------------- counting

define void @l0_inc(i64 %p) {
entry:
  %z = icmp eq i64 %p, 0
  br i1 %z, label %done, label %go
go:
  %hp = sub i64 %p, 8
  %hq = inttoptr i64 %hp to ptr
  %h = load i64, ptr %hq
  %rc = lshr i64 %h, 40
  %never = icmp eq i64 %rc, 16777215
  br i1 %never, label %done, label %alive
alive:
  %freed = icmp eq i64 %rc, 0
  br i1 %freed, label %uaf, label %bump
uaf:
  call void @rt_error(ptr @m_uaf, i64 20)
  unreachable
bump:
  %h1 = add i64 %h, 1099511627776
  store i64 %h1, ptr %hq
  br label %done
done:
  ret void
}

define void @l0_dec(i64 %p) {
entry:
  %z = icmp eq i64 %p, 0
  br i1 %z, label %done, label %go
go:
  %last = call i1 @dec_ref(i64 %p)
  br i1 %last, label %free, label %done
free:
  call void @free_from(i64 %p)
  br label %done
done:
  ret void
}

; Drops one reference to the nonzero p, and says whether it was the last. A
; count that stuck at its maximum is never freed.
define internal i1 @dec_ref(i64 %p) {
entry:
  %hp = sub i64 %p, 8
  %hq = inttoptr i64 %hp to ptr
  %h = load i64, ptr %hq
  %rc = lshr i64 %h, 40
  %never = icmp eq i64 %rc, 16777215
  br i1 %never, label %keep, label %alive
alive:
  %freed = icmp eq i64 %rc, 0
  br i1 %freed, label %uaf, label %which
uaf:
  call void @rt_error(ptr @m_uaf, i64 20)
  unreachable
which:
  %one = icmp eq i64 %rc, 1
  br i1 %one, label %gone, label %drop
drop:
  %h1 = sub i64 %h, 1099511627776
  store i64 %h1, ptr %hq
  br label %keep
keep:
  ret i1 false
gone:
  ret i1 true
}

define internal void @wl_push(i64 %p) {
entry:
  %n = load i64, ptr @wl_len
  %cap = load i64, ptr @wl_cap
  %full = icmp eq i64 %n, %cap
  br i1 %full, label %grow, label %put
grow:
  %none = icmp eq i64 %cap, 0
  %c2 = mul i64 %cap, 2
  %c3 = select i1 %none, i64 1024, i64 %c2
  %bytes = mul i64 %c3, 8
  %old = load ptr, ptr @wl
  %new = call ptr @host_resize(ptr %old, i64 %bytes)
  %bad = icmp eq ptr %new, null
  br i1 %bad, label %oom, label %grown
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
grown:
  store ptr %new, ptr @wl
  store i64 %c3, ptr @wl_cap
  br label %put
put:
  %arr = load ptr, ptr @wl
  %ep = getelementptr i64, ptr %arr, i64 %n
  store i64 %p, ptr %ep
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @wl_len
  ret void
}

; Frees p, whose last reference is gone, and every block only it kept alive.
define internal void @free_from(i64 %p) {
entry:
  call void @wl_push(i64 %p)
  br label %loop
loop:
  %n = load i64, ptr @wl_len
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %done, label %pop
pop:
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr @wl_len
  %arr = load ptr, ptr @wl
  %ep = getelementptr i64, ptr %arr, i64 %n1
  %q = load i64, ptr %ep
  call void @free_block(i64 %q)
  br label %loop
done:
  ret void
}

; Drops a reference to each block q points to, queueing any whose count
; reaches zero, then gives q back.
define internal void @free_block(i64 %q) {
entry:
  %hp = sub i64 %q, 8
  %hq = inttoptr i64 %hp to ptr
  %h = load i64, ptr %hq
  %mask = and i64 %h, 4294967295
  %sh = lshr i64 %h, 32
  %size = and i64 %sh, 255
  %qq = inttoptr i64 %q to ptr
  %isarr = icmp eq i64 %size, 0
  br i1 %isarr, label %arr, label %scan
arr:
  call void @free_array(i64 %q, i64 %h)
  ret void
scan:
  %k = phi i64 [ 0, %entry ], [ %k1, %next ]
  %end = icmp eq i64 %k, %size
  br i1 %end, label %release, label %bit
bit:
  %b = lshr i64 %mask, %k
  %b1 = and i64 %b, 1
  %isp = icmp ne i64 %b1, 0
  br i1 %isp, label %child, label %next
child:
  %cp = getelementptr i64, ptr %qq, i64 %k
  %c = load i64, ptr %cp
  %cz = icmp eq i64 %c, 0
  br i1 %cz, label %next, label %cdec
cdec:
  %last = call i1 @dec_ref(i64 %c)
  br i1 %last, label %push, label %next
push:
  call void @wl_push(i64 %c)
  br label %next
next:
  %k1 = add i64 %k, 1
  br label %scan
release:
  %lv = load i64, ptr @live
  %lv1 = sub i64 %lv, 1
  store i64 %lv1, ptr @live
  %chk = load i64, ptr @rc_check
  %checking = icmp ne i64 %chk, 0
  br i1 %checking, label %poison, label %recycle
poison:
  %hkeep = and i64 %h, 1099511627775
  store i64 %hkeep, ptr %hq
  br label %ploop
ploop:
  %j = phi i64 [ 0, %poison ], [ %j1, %pstep ]
  %pend = icmp eq i64 %j, %size
  br i1 %pend, label %out, label %pstep
pstep:
  %pp = getelementptr i64, ptr %qq, i64 %j
  store i64 6510615555426900570, ptr %pp
  %j1 = add i64 %j, 1
  br label %ploop
recycle:
  %total = add i64 %size, 1
  %fp = getelementptr [257 x i64], ptr @free_lists, i64 0, i64 %total
  %top = load i64, ptr %fp
  store i64 %top, ptr %hq
  store i64 %hp, ptr %fp
  %fb = load i64, ptr @free_bytes
  %tb = mul i64 %total, 8
  %fb1 = add i64 %fb, %tb
  store i64 %fb1, ptr @free_bytes
  br label %out
out:
  ret void
}

; Under L0_RC_CHECK, reports counted blocks still live at a normal exit.
define internal void @check_live() {
entry:
  call void @arr_stats()
  %chk = load i64, ptr @rc_check
  %on = icmp ne i64 %chk, 0
  br i1 %on, label %count, label %done
count:
  %lv = load i64, ptr @live
  %any = icmp ne i64 %lv, 0
  br i1 %any, label %report, label %done
report:
  call void @write_all(i32 2, ptr @m_live, i64 23)
  call void @write_int(i32 2, i64 %lv)
  br label %done
done:
  ret void
}

; A counted cons cell. mask is 2 when its head is a plain word and 3 when
; the head is a pointer too.
define i64 @l0_new_cons(i64 %h, i64 %t, i64 %mask) {
entry:
  %p = call i64 @cons_with(i64 %h, i64 %t, i64 %mask, i64 1)
  ret i64 %p
}

; A counted data block for n fields, with mask marking its pointer words.
define i64 @l0_new_data(i64 %tag, i64 %n, i64 %mask) {
entry:
  %p = call i64 @data_with(i64 %tag, i64 %n, i64 %mask, i64 1)
  ret i64 %p
}

; ------------------------------------------------------- lists and blocks

; The allocation calls from before counting, for code an older compiler
; emitted. Their blocks are never freed.
define i64 @l0_cons(i64 %h, i64 %t) {
entry:
  %p = call i64 @cons_with(i64 %h, i64 %t, i64 2, i64 16777215)
  ret i64 %p
}

define i64 @l0_head(i64 %l) {
entry:
  %e = icmp eq i64 %l, 0
  br i1 %e, label %err, label %ok
err:
  call void @rt_error(ptr @m_head, i64 18)
  unreachable
ok:
  %q = inttoptr i64 %l to ptr
  %v = load i64, ptr %q
  ret i64 %v
}

define i64 @l0_tail(i64 %l) {
entry:
  %e = icmp eq i64 %l, 0
  br i1 %e, label %err, label %ok
err:
  call void @rt_error(ptr @m_tail, i64 18)
  unreachable
ok:
  %q = inttoptr i64 %l to ptr
  %q1 = getelementptr i64, ptr %q, i64 1
  %v = load i64, ptr %q1
  ret i64 %v
}

define i64 @l0_is_empty(i64 %l) {
entry:
  %e = icmp eq i64 %l, 0
  %r = zext i1 %e to i64
  ret i64 %r
}

define i64 @l0_data_new(i64 %tag, i64 %n) {
entry:
  %p = call i64 @data_with(i64 %tag, i64 %n, i64 0, i64 16777215)
  ret i64 %p
}

define void @l0_data_set(i64 %b, i64 %i, i64 %v) {
entry:
  %q = inttoptr i64 %b to ptr
  %i1 = add i64 %i, 1
  %f = getelementptr i64, ptr %q, i64 %i1
  store i64 %v, ptr %f
  ret void
}

define i64 @l0_data_tag(i64 %b) {
entry:
  %q = inttoptr i64 %b to ptr
  %v = load i64, ptr %q
  ret i64 %v
}

define i64 @l0_data_get(i64 %b, i64 %i) {
entry:
  %q = inttoptr i64 %b to ptr
  %i1 = add i64 %i, 1
  %f = getelementptr i64, ptr %q, i64 %i1
  %v = load i64, ptr %f
  ret i64 %v
}

; ------------------------------------------------------------------ arrays
;
; An array is a block whose header has size 0, which no other block has: a
; cons cell is 2 words and a data block at least 1. Word 0 is the length and
; the elements follow, so element i is word i + 1. Mask bit 0 says whether
; the elements are pointers. Arrays come from malloc and go back to free,
; since their sizes are any number of words, and a page's blocks are one.
;
; array_set consumes its array: when that was the only reference it stores in
; place, and otherwise it copies. L0_ARRAY_STATS in the environment reports
; how many of each at a normal exit.

@arr_copies = internal global i64 0
@arr_inplace = internal global i64 0
@arr_words = internal global i64 0

define internal i64 @arr_alloc(i64 %n, i64 %p) {
entry:
  %huge = icmp ugt i64 %n, 1099511627776
  br i1 %huge, label %oom, label %try
try:
  %w = add i64 %n, 2
  %bytes = mul i64 %w, 8
  %m = call ptr @host_alloc(i64 %bytes)
  %null = icmp eq ptr %m, null
  br i1 %null, label %oom, label %ok
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
ok:
  %lv = load i64, ptr @live
  %lv1 = add i64 %lv, 1
  store i64 %lv1, ptr @live
  %hdr = or i64 1099511627776, %p
  store i64 %hdr, ptr %m
  %lp = getelementptr i64, ptr %m, i64 1
  store i64 %n, ptr %lp
  %a = ptrtoint ptr %lp to i64
  ret i64 %a
}

; Adds k references to the nonzero p at once, stopping at the count that
; means never freed.
define internal void @add_refs(i64 %p, i64 %k) {
entry:
  %hp = sub i64 %p, 8
  %hq = inttoptr i64 %hp to ptr
  %h = load i64, ptr %hq
  %rc = lshr i64 %h, 40
  %never = icmp eq i64 %rc, 16777215
  br i1 %never, label %done, label %go
go:
  %sum = add i64 %rc, %k
  %over = icmp ugt i64 %sum, 16777215
  %nrc = select i1 %over, i64 16777215, i64 %sum
  %low = and i64 %h, 1099511627775
  %sh = shl i64 %nrc, 40
  %nh = or i64 %low, %sh
  store i64 %nh, ptr %hq
  br label %done
done:
  ret void
}

; n copies of x, which comes with one reference; the array keeps n. p is 1
; when elements are pointers.
define i64 @l0_array_new(i64 %n, i64 %x, i64 %p) {
entry:
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %err, label %ok
err:
  call void @rt_error(ptr @m_alen, i64 21)
  unreachable
ok:
  %a = call i64 @arr_alloc(i64 %n, i64 %p)
  %q = inttoptr i64 %a to ptr
  br label %fill
fill:
  %k = phi i64 [ 0, %ok ], [ %k1, %put ]
  %full = icmp eq i64 %k, %n
  br i1 %full, label %refs, label %put
put:
  %k1 = add i64 %k, 1
  %ep = getelementptr i64, ptr %q, i64 %k1
  store i64 %x, ptr %ep
  br label %fill
refs:
  %isp = icmp ne i64 %p, 0
  %nz = icmp ne i64 %x, 0
  %counted = and i1 %isp, %nz
  br i1 %counted, label %adjust, label %done
adjust:
  %none = icmp eq i64 %n, 0
  br i1 %none, label %drop, label %more
drop:
  call void @l0_dec(i64 %x)
  br label %done
more:
  %extra = sub i64 %n, 1
  call void @add_refs(i64 %x, i64 %extra)
  br label %done
done:
  ret i64 %a
}

define i64 @l0_array_len(i64 %a) {
entry:
  %q = inttoptr i64 %a to ptr
  %n = load i64, ptr %q
  ret i64 %n
}

define i64 @l0_array_get(i64 %a, i64 %i) {
entry:
  %q = inttoptr i64 %a to ptr
  %n = load i64, ptr %q
  %in = icmp ult i64 %i, %n
  br i1 %in, label %ok, label %err
err:
  call void @rt_error(ptr @m_range, i64 24)
  unreachable
ok:
  %i1 = add i64 %i, 1
  %ep = getelementptr i64, ptr %q, i64 %i1
  %v = load i64, ptr %ep
  ret i64 %v
}

define i64 @l0_array_set(i64 %a, i64 %i, i64 %x) {
entry:
  %q = inttoptr i64 %a to ptr
  %n = load i64, ptr %q
  %in = icmp ult i64 %i, %n
  br i1 %in, label %ok, label %err
err:
  call void @rt_error(ptr @m_range, i64 24)
  unreachable
ok:
  %hp = getelementptr i64, ptr %q, i64 -1
  %h = load i64, ptr %hp
  %rc = lshr i64 %h, 40
  %p = and i64 %h, 1
  %isp = icmp ne i64 %p, 0
  %i1 = add i64 %i, 1
  %alone = icmp eq i64 %rc, 1
  br i1 %alone, label %inplace, label %copy
inplace:
  %ci = load i64, ptr @arr_inplace
  %ci1 = add i64 %ci, 1
  store i64 %ci1, ptr @arr_inplace
  %ep = getelementptr i64, ptr %q, i64 %i1
  %old = load i64, ptr %ep
  store i64 %x, ptr %ep
  br i1 %isp, label %release, label %same
release:
  call void @l0_dec(i64 %old)
  br label %same
same:
  ret i64 %a
copy:
  %cc = load i64, ptr @arr_copies
  %cc1 = add i64 %cc, 1
  store i64 %cc1, ptr @arr_copies
  %cw = load i64, ptr @arr_words
  %cw1 = add i64 %cw, %n
  store i64 %cw1, ptr @arr_words
  %b = call i64 @arr_alloc(i64 %n, i64 %p)
  %bq = inttoptr i64 %b to ptr
  %src = getelementptr i64, ptr %q, i64 1
  %dst = getelementptr i64, ptr %bq, i64 1
  %bytes = mul i64 %n, 8
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %bytes, i1 false)
  br i1 %isp, label %share, label %store
share:
  %k = phi i64 [ 1, %copy ], [ %k1, %snext ]
  %end = icmp ugt i64 %k, %n
  br i1 %end, label %store, label %sbody
sbody:
  %skip = icmp eq i64 %k, %i1
  br i1 %skip, label %snext, label %sinc
sinc:
  %sp = getelementptr i64, ptr %bq, i64 %k
  %sv = load i64, ptr %sp
  call void @l0_inc(i64 %sv)
  br label %snext
snext:
  %k1 = add i64 %k, 1
  br label %share
store:
  %bp = getelementptr i64, ptr %bq, i64 %i1
  store i64 %x, ptr %bp
  call void @l0_dec(i64 %a)
  ret i64 %b
}

; a itself if nothing else holds it, and otherwise a copy of it, holding a
; reference to each pointer element, with a released. Spec 10.3.
define internal i64 @arr_own(i64 %a) {
entry:
  %q = inttoptr i64 %a to ptr
  %hp = getelementptr i64, ptr %q, i64 -1
  %h = load i64, ptr %hp
  %rc = lshr i64 %h, 40
  %alone = icmp eq i64 %rc, 1
  br i1 %alone, label %mine, label %copy
mine:
  ret i64 %a
copy:
  %n = load i64, ptr %q
  %cc = load i64, ptr @arr_copies
  %cc1 = add i64 %cc, 1
  store i64 %cc1, ptr @arr_copies
  %cw = load i64, ptr @arr_words
  %cw1 = add i64 %cw, %n
  store i64 %cw1, ptr @arr_words
  %p = and i64 %h, 1
  %b = call i64 @arr_alloc(i64 %n, i64 %p)
  %bq = inttoptr i64 %b to ptr
  %src = getelementptr i64, ptr %q, i64 1
  %dst = getelementptr i64, ptr %bq, i64 1
  %bytes = mul i64 %n, 8
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %bytes, i1 false)
  %isp = icmp ne i64 %p, 0
  br i1 %isp, label %share, label %done
share:
  %k = phi i64 [ 1, %copy ], [ %k1, %sinc ]
  %end = icmp ugt i64 %k, %n
  br i1 %end, label %done, label %sinc
sinc:
  %sp = getelementptr i64, ptr %bq, i64 %k
  %sv = load i64, ptr %sp
  call void @l0_inc(i64 %sv)
  %k1 = add i64 %k, 1
  br label %share
done:
  call void @l0_dec(i64 %a)
  ret i64 %b
}

; (array_set g y (array_set (array_get g y) x v)) without giving row y a
; second holder, spec 6.5: g is made its own, then row y's slot hands its
; reference to l0_array_set, which updates the row in place if nothing else
; holds it and copies it otherwise, and the result goes back in the slot.
; The compiler has already checked y, before evaluating x and v.
define i64 @l0_array_set_row(i64 %g, i64 %y, i64 %x, i64 %v) {
entry:
  %g1 = call i64 @arr_own(i64 %g)
  %q = inttoptr i64 %g1 to ptr
  %n = load i64, ptr %q
  %in = icmp ult i64 %y, %n
  br i1 %in, label %ok, label %err
err:
  call void @rt_error(ptr @m_range, i64 24)
  unreachable
ok:
  %y1 = add i64 %y, 1
  %rp = getelementptr i64, ptr %q, i64 %y1
  %row = load i64, ptr %rp
  %nr = call i64 @l0_array_set(i64 %row, i64 %x, i64 %v)
  store i64 %nr, ptr %rp
  ret i64 %g1
}

; The element (array_get g y) gives in the form of spec section 6.5 that
; hands it through a function and back, with a reference the caller owns.
; When g has no other holder it is taken out, a 0 left in its place for the
; outer array_set to release; otherwise it gets a reference of its own, as
; l0_array_get's result does. Nothing is allocated either way. The compiler
; emits this only for an array whose elements are counted.
define i64 @l0_array_take(i64 %g, i64 %y) {
entry:
  %q = inttoptr i64 %g to ptr
  %n = load i64, ptr %q
  %in = icmp ult i64 %y, %n
  br i1 %in, label %ok, label %err
err:
  call void @rt_error(ptr @m_range, i64 24)
  unreachable
ok:
  %y1 = add i64 %y, 1
  %ep = getelementptr i64, ptr %q, i64 %y1
  %e = load i64, ptr %ep
  %hp = getelementptr i64, ptr %q, i64 -1
  %h = load i64, ptr %hp
  %rc = lshr i64 %h, 40
  %alone = icmp eq i64 %rc, 1
  br i1 %alone, label %take, label %share
take:
  store i64 0, ptr %ep
  ret i64 %e
share:
  call void @l0_inc(i64 %e)
  ret i64 %e
}

; Drops a reference to each pointer element of the array q, queueing any
; whose count reaches zero, then gives q back to malloc. Under L0_RC_CHECK
; it is kept, with a count of 0 and a length of 0, so a later use is caught.
define internal void @free_array(i64 %q, i64 %h) {
entry:
  %qq = inttoptr i64 %q to ptr
  %n = load i64, ptr %qq
  %p = and i64 %h, 1
  %isp = icmp ne i64 %p, 0
  br i1 %isp, label %scan, label %release
scan:
  %k = phi i64 [ 1, %entry ], [ %k1, %next ]
  %end = icmp ugt i64 %k, %n
  br i1 %end, label %release, label %elem
elem:
  %cp = getelementptr i64, ptr %qq, i64 %k
  %c = load i64, ptr %cp
  %cz = icmp eq i64 %c, 0
  br i1 %cz, label %next, label %cdec
cdec:
  %last = call i1 @dec_ref(i64 %c)
  br i1 %last, label %push, label %next
push:
  call void @wl_push(i64 %c)
  br label %next
next:
  %k1 = add i64 %k, 1
  br label %scan
release:
  %lv = load i64, ptr @live
  %lv1 = sub i64 %lv, 1
  store i64 %lv1, ptr @live
  %hp = sub i64 %q, 8
  %hq = inttoptr i64 %hp to ptr
  %chk = load i64, ptr @rc_check
  %checking = icmp ne i64 %chk, 0
  br i1 %checking, label %poison, label %give
poison:
  %hkeep = and i64 %h, 1099511627775
  store i64 %hkeep, ptr %hq
  store i64 0, ptr %qq
  ret void
give:
  call void @l0_host_free(ptr %hq)
  ret void
}

define internal void @arr_stats() {
entry:
  %e = call ptr @l0_host_setting(ptr @stats_name)
  %on = icmp ne ptr %e, null
  br i1 %on, label %report, label %done
report:
  %c = load i64, ptr @arr_copies
  call void @write_all(i32 2, ptr @m_copies, i64 18)
  call void @write_int(i32 2, i64 %c)
  %i = load i64, ptr @arr_inplace
  call void @write_all(i32 2, ptr @m_inplace, i64 25)
  call void @write_int(i32 2, i64 %i)
  %w = load i64, ptr @arr_words
  call void @write_all(i32 2, ptr @m_words, i64 24)
  call void @write_int(i32 2, i64 %w)
  br label %done
done:
  ret void
}

; -------------------------------------------------------------- arithmetic

; Calls rather than instructions, so that generated IR contains no error
; checking, and so that the cases LLVM leaves undefined get L0's wrapping
; result. Spec section 6.1. Dividing by -1 is negation for every dividend,
; including the most negative one, and the remainder is always 0.

define i64 @l0_div(i64 %a, i64 %b) {
entry:
  %z = icmp eq i64 %b, 0
  br i1 %z, label %err, label %chk
err:
  call void @rt_error(ptr @m_div, i64 16)
  unreachable
chk:
  %m1 = icmp eq i64 %b, -1
  br i1 %m1, label %neg, label %do
neg:
  %r0 = sub i64 0, %a
  ret i64 %r0
do:
  %r = sdiv i64 %a, %b
  ret i64 %r
}

define i64 @l0_mod(i64 %a, i64 %b) {
entry:
  %z = icmp eq i64 %b, 0
  br i1 %z, label %err, label %chk
err:
  call void @rt_error(ptr @m_mod, i64 14)
  unreachable
chk:
  %m1 = icmp eq i64 %b, -1
  br i1 %m1, label %zero, label %do
zero:
  ret i64 0
do:
  %r = srem i64 %a, %b
  ret i64 %r
}

; Spec section 6.10. An LLVM shift by 64 or more is poison, and L0's is every
; bit shifted out, 0; a negative amount is a runtime error.
define i64 @l0_bit_shl(i64 %a, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %err, label %chk
err:
  call void @rt_error(ptr @m_shift, i64 14)
  unreachable
chk:
  %out = icmp sge i64 %n, 64
  br i1 %out, label %zero, label %do
zero:
  ret i64 0
do:
  %r = shl i64 %a, %n
  ret i64 %r
}

define i64 @l0_bit_shr(i64 %a, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %err, label %chk
err:
  call void @rt_error(ptr @m_shift, i64 14)
  unreachable
chk:
  %out = icmp sge i64 %n, 64
  br i1 %out, label %zero, label %do
zero:
  ret i64 0
do:
  %r = lshr i64 %a, %n
  ret i64 %r
}

define i64 @l0_bit_count(i64 %a) {
entry:
  %r = call i64 @llvm.ctpop.i64(i64 %a)
  ret i64 %r
}

; ----------------------------------------------------------------- handles

; Whether h names a handle open in mode.
define internal i1 @h_is(i64 %h, i64 %mode) {
entry:
  %lo = icmp sge i64 %h, 0
  %hi = icmp slt i64 %h, 64
  %in = and i1 %lo, %hi
  br i1 %in, label %chk, label %no
chk:
  %mp = getelementptr [64 x i64], ptr @h_mode, i64 0, i64 %h
  %m = load i64, ptr %mp
  %eq = icmp eq i64 %m, %mode
  ret i1 %eq
no:
  ret i1 false
}

define internal void @h_set(i64 %h, i64 %fd, i64 %mode, ptr %buf) {
entry:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  store i64 0, ptr %kp
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  store i64 %fd, ptr %fp
  %mp = getelementptr [64 x i64], ptr @h_mode, i64 0, i64 %h
  store i64 %mode, ptr %mp
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  store i64 0, ptr %sp
  %ep = getelementptr [64 x i64], ptr @h_err, i64 0, i64 %h
  store i64 0, ptr %ep
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  store ptr %buf, ptr %bp
  %pp = getelementptr [64 x i64], ptr @h_pos, i64 0, i64 %h
  store i64 0, ptr %pp
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  store i64 0, ptr %lp
  ret void
}

define internal void @std_handles() {
entry:
  call void @h_set(i64 0, i64 0, i64 1, ptr @in_buf)
  call void @h_set(i64 1, i64 1, i64 2, ptr @out_buf)
  call void @h_set(i64 2, i64 2, i64 2, ptr @err_buf)
  ret void
}

; Delivers what a writing handle holds back. Returns 0, or -5 if this or an
; earlier write to the handle failed. It reports nothing; a caller whose
; result reaches the program marks the failure reported.
define internal i64 @h_flush(i64 %h) {
entry:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %buffer = icmp eq i64 %k, 2
  br i1 %buffer, label %kept, label %descriptor
kept:
  ret i64 0
descriptor:
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %n = load i64, ptr %lp
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  %any = icmp sgt i64 %n, 0
  br i1 %any, label %write, label %done
write:
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  %fd = load i64, ptr %fp
  %fd32 = trunc i64 %fd to i32
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %buf = load ptr, ptr %bp
  %rc = call i64 @write_all_rc(i32 %fd32, ptr %buf, i64 %n)
  store i64 0, ptr %lp
  %bad = icmp ne i64 %rc, 0
  br i1 %bad, label %failed, label %done
failed:
  store i64 3, ptr %sp
  %ep = getelementptr [64 x i64], ptr @h_err, i64 0, i64 %h
  %was = load i64, ptr %ep
  %first = icmp eq i64 %was, 0
  %keep = select i1 %first, i64 %rc, i64 %was
  store i64 %keep, ptr %ep
  br label %done
done:
  %st = load i64, ptr %sp
  %err = icmp uge i64 %st, 3
  %ep2 = getelementptr [64 x i64], ptr @h_err, i64 0, i64 %h
  %code = load i64, ptr %ep2
  %none = icmp eq i64 %code, 0
  %lost = select i1 %none, i64 -5, i64 %code
  %r = select i1 %err, i64 %lost, i64 0
  ret i64 %r
}

define i64 @l0_flush(i64 %h) {
entry:
  %ok = call i1 @h_is(i64 %h, i64 2)
  br i1 %ok, label %go, label %bad
bad:
  ret i64 -2
go:
  %r = call i64 @h_flush(i64 %h)
  %failed = icmp ne i64 %r, 0
  br i1 %failed, label %told, label %done
told:
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  store i64 4, ptr %sp
  br label %done
done:
  ret i64 %r
}

; After the last flush of a normal exit: a write failure on a handle still
; open that no flush reported is the runtime error of spec section 6.3. A
; closed handle has been reported by its close.
define internal void @report_lost() {
entry:
  br label %loop
loop:
  %h = phi i64 [ 0, %entry ], [ %h1, %next ]
  %end = icmp eq i64 %h, 64
  br i1 %end, label %done, label %body
body:
  %w = call i1 @h_is(i64 %h, i64 2)
  br i1 %w, label %chk, label %next
chk:
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  %st = load i64, ptr %sp
  %lost = icmp eq i64 %st, 3
  br i1 %lost, label %fail, label %next
fail:
  call void @rt_error(ptr @m_write, i64 12)
  unreachable
next:
  %h1 = add i64 %h, 1
  br label %loop
done:
  ret void
}

; Standard output and standard error, before a read that may wait. Spec
; section 6.3.
define internal void @flush_std() {
entry:
  %a = call i64 @h_flush(i64 1)
  %b = call i64 @h_flush(i64 2)
  ret void
}

; Every writing handle, when the program ends.
define internal void @flush_every() {
entry:
  br label %loop
loop:
  %h = phi i64 [ 0, %entry ], [ %h1, %next ]
  %end = icmp eq i64 %h, 64
  br i1 %end, label %done, label %body
body:
  %w = call i1 @h_is(i64 %h, i64 2)
  br i1 %w, label %flush, label %next
flush:
  %r = call i64 @h_flush(i64 %h)
  br label %next
next:
  %h1 = add i64 %h, 1
  br label %loop
done:
  ret void
}

; Standard output and error are flushed before every read of a descriptor,
; since that read may wait.
define i64 @l0_read_from(i64 %h) {
entry:
  %ok = call i1 @h_is(i64 %h, i64 1)
  br i1 %ok, label %state, label %bad
bad:
  ret i64 -2
state:
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  %st = load i64, ptr %sp
  %eof = icmp eq i64 %st, 1
  br i1 %eof, label %ended, label %chkerr
chkerr:
  %err = icmp eq i64 %st, 2
  br i1 %err, label %failed, label %kind
kind:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %list = icmp eq i64 %k, 1
  br i1 %list, label %cell, label %chk
cell:
  %cp0 = getelementptr [64 x i64], ptr @h_pos, i64 0, i64 %h
  %cur = load i64, ptr %cp0
  %last = icmp eq i64 %cur, 0
  br i1 %last, label %listend, label %elem
listend:
  store i64 1, ptr %sp
  br label %ended
elem:
  %cq = inttoptr i64 %cur to ptr
  %ev = load i64, ptr %cq
  %np = getelementptr i64, ptr %cq, i64 1
  %next = load i64, ptr %np
  store i64 %next, ptr %cp0
  %eb = and i64 %ev, 255
  ret i64 %eb
chk:
  %pp = getelementptr [64 x i64], ptr @h_pos, i64 0, i64 %h
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %buf = load ptr, ptr %bp
  %pos = load i64, ptr %pp
  %len = load i64, ptr %lp
  %have = icmp slt i64 %pos, %len
  br i1 %have, label %take, label %fill
fill:
  call void @flush_std()
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  %fd = load i64, ptr %fp
  %n = call i64 @l0_host_read(i64 %fd, ptr %buf, i64 65536)
  %got = icmp sgt i64 %n, 0
  br i1 %got, label %filled, label %nothing
nothing:
  %zero = icmp eq i64 %n, 0
  %ns = select i1 %zero, i64 1, i64 2
  store i64 %ns, ptr %sp
  br i1 %zero, label %ended, label %failed
filled:
  store i64 %n, ptr %lp
  store i64 0, ptr %pp
  br label %take
take:
  %p = phi i64 [ %pos, %chk ], [ 0, %filled ]
  %cp = getelementptr i8, ptr %buf, i64 %p
  %b = load i8, ptr %cp
  %v = zext i8 %b to i64
  %p1 = add i64 %p, 1
  store i64 %p1, ptr %pp
  ret i64 %v
ended:
  ret i64 -1
failed:
  ret i64 -5
}

define i64 @l0_write_to(i64 %h, i64 %v) {
entry:
  %ok = call i1 @h_is(i64 %h, i64 2)
  br i1 %ok, label %go, label %bad
bad:
  ret i64 -2
go:
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %n = load i64, ptr %lp
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %buffer = icmp eq i64 %k, 2
  br i1 %buffer, label %keep, label %descriptor
descriptor:
  %full = icmp eq i64 %n, 65536
  br i1 %full, label %flush, label %put
flush:
  %r = call i64 @h_flush(i64 %h)
  br label %put
keep:
  %cpp = getelementptr [64 x i64], ptr @h_cap, i64 0, i64 %h
  %cap = load i64, ptr %cpp
  %room = icmp slt i64 %n, %cap
  br i1 %room, label %put, label %grow
grow:
  %ncap = shl i64 %cap, 1
  %ob = load ptr, ptr %bp
  %nb = call ptr @host_resize(ptr %ob, i64 %ncap)
  %oom = icmp eq ptr %nb, null
  br i1 %oom, label %exhausted, label %grown
exhausted:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
grown:
  store ptr %nb, ptr %bp
  store i64 %ncap, ptr %cpp
  br label %put
put:
  %n1 = phi i64 [ %n, %descriptor ], [ 0, %flush ], [ %n, %keep ], [ %n, %grown ]
  %buf = load ptr, ptr %bp
  %cp = getelementptr i8, ptr %buf, i64 %n1
  %b = trunc i64 %v to i8
  store i8 %b, ptr %cp
  %n2 = add i64 %n1, 1
  store i64 %n2, ptr %lp
  ret i64 0
}

define i64 @l0_read_byte() {
entry:
  %r = call i64 @l0_read_from(i64 0)
  ret i64 %r
}

; ---------------------------------------------------------- reading it all

; Makes the buffer at bufp, of the capacity at capp, hold at least need
; bytes, doubling it as often as that takes.
define internal void @buf_reserve(ptr %bufp, ptr %capp, i64 %need) {
entry:
  %cap = load i64, ptr %capp
  %ok = icmp uge i64 %cap, %need
  br i1 %ok, label %done, label %dbl
dbl:
  %c = phi i64 [ %cap, %entry ], [ %c2, %dbl ]
  %c2 = shl i64 %c, 1
  %enough = icmp uge i64 %c2, %need
  br i1 %enough, label %re, label %dbl
re:
  %old = load ptr, ptr %bufp
  %new = call ptr @host_resize(ptr %old, i64 %c2)
  %null = icmp eq ptr %new, null
  br i1 %null, label %oom, label %grown
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
grown:
  store ptr %new, ptr %bufp
  store i64 %c2, ptr %capp
  br label %done
done:
  ret void
}

; Every byte left on h, a handle open for reading, in a buffer from malloc
; whose first pre bytes are left for the caller, with their count stored at
; lenp. It leaves h as read_from would at the end: in state 1 at end of
; input, or 2 if a read failed, so the next read_from says which; a handle
; already in either state gives nothing. The buffer doubles as it fills and
; is trimmed to fit at the end, so only realloc ever holds two copies.
define internal ptr @slurp(i64 %h, i64 %pre, ptr %lenp) {
entry:
  %bufp = alloca ptr
  %capp = alloca i64
  %np = alloca i64
  store i64 0, ptr %np
  %init = add i64 %pre, 65536
  %b0 = call ptr @host_alloc(i64 %init)
  %null = icmp eq ptr %b0, null
  br i1 %null, label %oom, label %start
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
start:
  store ptr %b0, ptr %bufp
  store i64 %init, ptr %capp
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  %st = load i64, ptr %sp
  %over = icmp ne i64 %st, 0
  br i1 %over, label %finish, label %kind
kind:
  %pp = getelementptr [64 x i64], ptr @h_pos, i64 0, i64 %h
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %list = icmp eq i64 %k, 1
  br i1 %list, label %lstart, label %dstart
lstart:
  %cur0 = load i64, ptr %pp
  br label %lloop
lloop:
  %cur = phi i64 [ %cur0, %lstart ], [ %next, %lbody ]
  %lend = icmp eq i64 %cur, 0
  br i1 %lend, label %ldone, label %lbody
lbody:
  %ln = load i64, ptr %np
  %loff = add i64 %pre, %ln
  %lneed = add i64 %loff, 1
  call void @buf_reserve(ptr %bufp, ptr %capp, i64 %lneed)
  %cq = inttoptr i64 %cur to ptr
  %ev = load i64, ptr %cq
  %eb = trunc i64 %ev to i8
  %lbuf = load ptr, ptr %bufp
  %ldst = getelementptr i8, ptr %lbuf, i64 %loff
  store i8 %eb, ptr %ldst
  %ln1 = add i64 %ln, 1
  store i64 %ln1, ptr %np
  %nextp = getelementptr i64, ptr %cq, i64 1
  %next = load i64, ptr %nextp
  br label %lloop
ldone:
  store i64 0, ptr %pp
  store i64 1, ptr %sp
  br label %finish
dstart:
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %hbp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %pos = load i64, ptr %pp
  %len = load i64, ptr %lp
  %hbuf = load ptr, ptr %hbp
  %rem = sub i64 %len, %pos
  %rneed = add i64 %pre, %rem
  call void @buf_reserve(ptr %bufp, ptr %capp, i64 %rneed)
  %dbuf = load ptr, ptr %bufp
  %ddst = getelementptr i8, ptr %dbuf, i64 %pre
  %dsrc = getelementptr i8, ptr %hbuf, i64 %pos
  call void @llvm.memcpy.p0.p0.i64(ptr %ddst, ptr %dsrc, i64 %rem, i1 false)
  store i64 %rem, ptr %np
  store i64 %len, ptr %pp
  call void @flush_std()
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  %fd = load i64, ptr %fp
  br label %rloop
rloop:
  %rn = load i64, ptr %np
  %rcap = load i64, ptr %capp
  %used = add i64 %pre, %rn
  %room = sub i64 %rcap, %used
  %has = icmp sgt i64 %room, 0
  br i1 %has, label %rread, label %rgrow
rgrow:
  %more = add i64 %rcap, 1
  call void @buf_reserve(ptr %bufp, ptr %capp, i64 %more)
  br label %rloop
rread:
  %rbuf = load ptr, ptr %bufp
  %rdst = getelementptr i8, ptr %rbuf, i64 %used
  %r = call i64 @l0_host_read(i64 %fd, ptr %rdst, i64 %room)
  %got = icmp sgt i64 %r, 0
  br i1 %got, label %radv, label %rstop
radv:
  %rn1 = add i64 %rn, %r
  store i64 %rn1, ptr %np
  br label %rloop
rstop:
  %zero = icmp eq i64 %r, 0
  %ns = select i1 %zero, i64 1, i64 2
  store i64 %ns, ptr %sp
  br label %finish
finish:
  %n = load i64, ptr %np
  store i64 %n, ptr %lenp
  %fbuf = load ptr, ptr %bufp
  %fsize = add i64 %pre, %n
  %fsize1 = add i64 %fsize, 8
  %trim = call ptr @host_resize(ptr %fbuf, i64 %fsize1)
  %tnull = icmp eq ptr %trim, null
  %res = select i1 %tnull, ptr %fbuf, ptr %trim
  ret ptr %res
}

; ------------------------------------------------------------------- bytes
;
; A bytes value is laid out as an array of ints is, a header of size 0 with
; mask bit 0 clear and then the length in word 0, but the bytes follow one
; per byte rather than one per word. free_block treats it as an array with
; no pointer elements, which is all it needs, and free gives it back.

@m_brange = private constant [23 x i8] c"byte index out of range"

; Marks the malloc block m, whose bytes start 16 past it, as a counted bytes
; value of length n, and returns it. Mask 2 is what tells bytes from an
; (array int) to @l0_equal; bit 0, which arrays read, is clear. Spec 10.1.
define internal i64 @bytes_mark(ptr %m, i64 %n) {
entry:
  %lv = load i64, ptr @live
  %lv1 = add i64 %lv, 1
  store i64 %lv1, ptr @live
  store i64 1099511627778, ptr %m
  %lp = getelementptr i64, ptr %m, i64 1
  store i64 %n, ptr %lp
  %b = ptrtoint ptr %lp to i64
  ret i64 %b
}

define internal i64 @bytes_alloc(i64 %n) {
entry:
  %huge = icmp ugt i64 %n, 1099511627776
  br i1 %huge, label %oom, label %try
try:
  %size = add i64 %n, 16
  %m = call ptr @host_alloc(i64 %size)
  %null = icmp eq ptr %m, null
  br i1 %null, label %oom, label %ok
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
ok:
  %b = call i64 @bytes_mark(ptr %m, i64 %n)
  ret i64 %b
}

; Every byte left on h, or none if h is not open for reading. Read straight
; into the block it is returned in.
define i64 @l0_read_bytes(i64 %h) {
entry:
  %lenp = alloca i64
  %ok = call i1 @h_is(i64 %h, i64 1)
  br i1 %ok, label %go, label %none
none:
  %e = call i64 @bytes_alloc(i64 0)
  ret i64 %e
go:
  %m = call ptr @slurp(i64 %h, i64 16, ptr %lenp)
  %n = load i64, ptr %lenp
  %b = call i64 @bytes_mark(ptr %m, i64 %n)
  ret i64 %b
}

@m_bcount = private constant [23 x i8] c"byte count out of range"

; Spec section 6.6: the next bytes on h, at least one and at most n, or none
; at the end, on a failure, or if h is not open for reading, leaving h's
; state for read_from to report, as read_from itself does. A descriptor
; gives what it holds back, after one read into its buffer if that is empty;
; a handle over a list gives its next cells.
define i64 @l0_read_some(i64 %h, i64 %n) {
entry:
  %few = icmp slt i64 %n, 1
  br i1 %few, label %err, label %open
err:
  call void @rt_error(ptr @m_bcount, i64 23)
  unreachable
open:
  %ok = call i1 @h_is(i64 %h, i64 1)
  br i1 %ok, label %state, label %none
none:
  %e = call i64 @bytes_alloc(i64 0)
  ret i64 %e
state:
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  %st = load i64, ptr %sp
  %stuck = icmp eq i64 %st, 0
  br i1 %stuck, label %kind, label %none
kind:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %list = icmp eq i64 %k, 1
  %pp = getelementptr [64 x i64], ptr @h_pos, i64 0, i64 %h
  br i1 %list, label %cells, label %chk
cells:
  %c0 = load i64, ptr %pp
  br label %count
count:
  %c = phi i64 [ %c0, %cells ], [ %cn, %cstep ]
  %m = phi i64 [ 0, %cells ], [ %m1, %cstep ]
  %cend = icmp eq i64 %c, 0
  %full = icmp eq i64 %m, %n
  %stop = or i1 %cend, %full
  br i1 %stop, label %counted, label %cstep
cstep:
  %cq = inttoptr i64 %c to ptr
  %cnp = getelementptr i64, ptr %cq, i64 1
  %cn = load i64, ptr %cnp
  %m1 = add i64 %m, 1
  br label %count
counted:
  %mz = icmp eq i64 %m, 0
  br i1 %mz, label %list_end, label %list_alloc
list_end:
  store i64 1, ptr %sp
  br label %none
list_alloc:
  %lb = call i64 @bytes_alloc(i64 %m)
  %lbq = inttoptr i64 %lb to ptr
  br label %fill
fill:
  %f = phi i64 [ %c0, %list_alloc ], [ %fn, %fstep ]
  %i = phi i64 [ 0, %list_alloc ], [ %i1, %fstep ]
  %fdone = icmp eq i64 %i, %m
  br i1 %fdone, label %list_done, label %fstep
fstep:
  %fq = inttoptr i64 %f to ptr
  %v = load i64, ptr %fq
  %v8 = trunc i64 %v to i8
  %o = add i64 %i, 8
  %dp = getelementptr i8, ptr %lbq, i64 %o
  store i8 %v8, ptr %dp
  %fnp = getelementptr i64, ptr %fq, i64 1
  %fn = load i64, ptr %fnp
  %i1 = add i64 %i, 1
  br label %fill
list_done:
  store i64 %f, ptr %pp
  ret i64 %lb
chk:
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %buf = load ptr, ptr %bp
  %pos = load i64, ptr %pp
  %len = load i64, ptr %lp
  %have = icmp slt i64 %pos, %len
  br i1 %have, label %take, label %refill
refill:
  call void @flush_std()
  %fdp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  %fd = load i64, ptr %fdp
  %r = call i64 @l0_host_read(i64 %fd, ptr %buf, i64 65536)
  %got = icmp sgt i64 %r, 0
  br i1 %got, label %filled, label %nothing
nothing:
  %zero = icmp eq i64 %r, 0
  %ns = select i1 %zero, i64 1, i64 2
  store i64 %ns, ptr %sp
  br label %none
filled:
  store i64 %r, ptr %lp
  store i64 0, ptr %pp
  br label %take
take:
  %p = phi i64 [ %pos, %chk ], [ 0, %filled ]
  %l = phi i64 [ %len, %chk ], [ %r, %filled ]
  %avail = sub i64 %l, %p
  %less = icmp slt i64 %n, %avail
  %t = select i1 %less, i64 %n, i64 %avail
  %tb = call i64 @bytes_alloc(i64 %t)
  %tbq = inttoptr i64 %tb to ptr
  %dst = getelementptr i8, ptr %tbq, i64 8
  %src = getelementptr i8, ptr %buf, i64 %p
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %t, i1 false)
  %p2 = add i64 %p, %t
  store i64 %p2, ptr %pp
  ret i64 %tb
}

define i64 @l0_bytes_len(i64 %b) {
entry:
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  ret i64 %n
}

define i64 @l0_bytes_get(i64 %b, i64 %i) {
entry:
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  %in = icmp ult i64 %i, %n
  br i1 %in, label %ok, label %err
err:
  call void @rt_error(ptr @m_brange, i64 23)
  unreachable
ok:
  %o = add i64 %i, 8
  %cp = getelementptr i8, ptr %q, i64 %o
  %c = load i8, ptr %cp
  %v = zext i8 %c to i64
  ret i64 %v
}

; The bytes of the list s, each taken modulo 256 as write_byte takes it.
; Consumes s.
define i64 @l0_bytes_from_list(i64 %s) {
entry:
  br label %count
count:
  %c = phi i64 [ %s, %entry ], [ %cn, %cstep ]
  %k = phi i64 [ 0, %entry ], [ %k1, %cstep ]
  %cend = icmp eq i64 %c, 0
  br i1 %cend, label %alloc, label %cstep
cstep:
  %cq = inttoptr i64 %c to ptr
  %cnp = getelementptr i64, ptr %cq, i64 1
  %cn = load i64, ptr %cnp
  %k1 = add i64 %k, 1
  br label %count
alloc:
  %b = call i64 @bytes_alloc(i64 %k)
  %bq = inttoptr i64 %b to ptr
  br label %fill
fill:
  %f = phi i64 [ %s, %alloc ], [ %fn, %fstep ]
  %i = phi i64 [ 8, %alloc ], [ %i1, %fstep ]
  %fend = icmp eq i64 %f, 0
  br i1 %fend, label %done, label %fstep
fstep:
  %fq = inttoptr i64 %f to ptr
  %v = load i64, ptr %fq
  %v8 = trunc i64 %v to i8
  %dp = getelementptr i8, ptr %bq, i64 %i
  store i8 %v8, ptr %dp
  %fnp = getelementptr i64, ptr %fq, i64 1
  %fn = load i64, ptr %fnp
  %i1 = add i64 %i, 1
  br label %fill
done:
  %nz = icmp ne i64 %s, 0
  br i1 %nz, label %rel, label %out
rel:
  call void @l0_dec(i64 %s)
  br label %out
out:
  ret i64 %b
}

; The bytes of b as a list. Consumes b.
define i64 @l0_bytes_to_list(i64 %b) {
entry:
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %i1, %cons ]
  %acc = phi i64 [ 0, %entry ], [ %acc1, %cons ]
  %done = icmp eq i64 %i, 0
  br i1 %done, label %out, label %cons
cons:
  %i1 = sub i64 %i, 1
  %o = add i64 %i1, 8
  %cp = getelementptr i8, ptr %q, i64 %o
  %c = load i8, ptr %cp
  %v = zext i8 %c to i64
  %acc1 = call i64 @l0_new_cons(i64 %v, i64 %acc, i64 2)
  br label %loop
out:
  call void @l0_dec(i64 %b)
  ret i64 %acc
}

; Bytes i up to j of b, as new bytes. i and j must be in order within b.
; Borrows b.
define i64 @l0_bytes_slice(i64 %b, i64 %i, i64 %j) {
entry:
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  %lo = icmp ule i64 %i, %j
  %hi = icmp ule i64 %j, %n
  %in = and i1 %lo, %hi
  br i1 %in, label %ok, label %err
err:
  call void @rt_error(ptr @m_brange, i64 23)
  unreachable
ok:
  %k = sub i64 %j, %i
  %r = call i64 @bytes_alloc(i64 %k)
  %rq = inttoptr i64 %r to ptr
  %dst = getelementptr i8, ptr %rq, i64 8
  %so = add i64 %i, 8
  %src = getelementptr i8, ptr %q, i64 %so
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %k, i1 false)
  ret i64 %r
}

; The bytes of each value on the list bs, in order, as new bytes. Borrows bs.
; A total past bytes_alloc's limit stops the count there, and bytes_alloc
; reports it, so the sum cannot wrap.
define i64 @l0_bytes_concat(i64 %bs) {
entry:
  br label %count
count:
  %c = phi i64 [ %bs, %entry ], [ %cn, %cstep ]
  %t = phi i64 [ 0, %entry ], [ %t1, %cstep ]
  %cend = icmp eq i64 %c, 0
  br i1 %cend, label %alloc, label %cstep
cstep:
  %cq = inttoptr i64 %c to ptr
  %e = load i64, ptr %cq
  %eq = inttoptr i64 %e to ptr
  %en = load i64, ptr %eq
  %t1 = add i64 %t, %en
  %cnp = getelementptr i64, ptr %cq, i64 1
  %cn = load i64, ptr %cnp
  %big = icmp ugt i64 %t1, 1099511627776
  br i1 %big, label %alloc, label %count
alloc:
  %total = phi i64 [ %t, %count ], [ %t1, %cstep ]
  %r = call i64 @bytes_alloc(i64 %total)
  %rq = inttoptr i64 %r to ptr
  br label %fill
fill:
  %f = phi i64 [ %bs, %alloc ], [ %fn, %fstep ]
  %at = phi i64 [ 8, %alloc ], [ %at1, %fstep ]
  %fend = icmp eq i64 %f, 0
  br i1 %fend, label %done, label %fstep
fstep:
  %fq = inttoptr i64 %f to ptr
  %x = load i64, ptr %fq
  %xq = inttoptr i64 %x to ptr
  %xn = load i64, ptr %xq
  %src = getelementptr i8, ptr %xq, i64 8
  %dst = getelementptr i8, ptr %rq, i64 %at
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %xn, i1 false)
  %at1 = add i64 %at, %xn
  %fnp = getelementptr i64, ptr %fq, i64 1
  %fn = load i64, ptr %fnp
  br label %fill
done:
  ret i64 %r
}

; Writes bytes i up to j of b to h, as write_to would one by one: 0, or -2
; if h is not open for writing. i and j must be in order within b.
define i64 @l0_write_bytes(i64 %h, i64 %b, i64 %i, i64 %j) {
entry:
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  %lo = icmp ule i64 %i, %j
  %hi = icmp ule i64 %j, %n
  %in = and i1 %lo, %hi
  br i1 %in, label %chk, label %err
err:
  call void @rt_error(ptr @m_brange, i64 23)
  unreachable
chk:
  %ok = call i1 @h_is(i64 %h, i64 2)
  br i1 %ok, label %which, label %bad
bad:
  ret i64 -2
which:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %kind = load i64, ptr %kp
  %isfd = icmp eq i64 %kind, 0
  br i1 %isfd, label %blocks, label %loop
; A descriptor's bytes go into its buffer a block at a time, delivered when
; it fills, exactly as write_to would put them there one by one.
blocks:
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  br label %block
block:
  %s = phi i64 [ %i, %blocks ], [ %s1, %copied ]
  %more = icmp ult i64 %s, %j
  br i1 %more, label %room, label %done
room:
  %held = load i64, ptr %lp
  %full = icmp eq i64 %held, 65536
  br i1 %full, label %deliver, label %copy
deliver:
  %fr = call i64 @h_flush(i64 %h)
  br label %copy
copy:
  %at = phi i64 [ %held, %room ], [ 0, %deliver ]
  %space = sub i64 65536, %at
  %left = sub i64 %j, %s
  %fits = icmp ult i64 %left, %space
  %cnt = select i1 %fits, i64 %left, i64 %space
  %buf = load ptr, ptr %bp
  %dst = getelementptr i8, ptr %buf, i64 %at
  %so = add i64 %s, 8
  %src = getelementptr i8, ptr %q, i64 %so
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %cnt, i1 false)
  %at1 = add i64 %at, %cnt
  store i64 %at1, ptr %lp
  %s1 = add i64 %s, %cnt
  br label %copied
copied:
  br label %block
loop:
  %k = phi i64 [ %i, %which ], [ %k1, %put ]
  %end = icmp eq i64 %k, %j
  br i1 %end, label %done, label %put
put:
  %o = add i64 %k, 8
  %cp = getelementptr i8, ptr %q, i64 %o
  %c = load i8, ptr %cp
  %v = zext i8 %c to i64
  %r = call i64 @l0_write_to(i64 %h, i64 %v)
  %k1 = add i64 %k, 1
  br label %loop
done:
  ret i64 0
}

; Releases the list a list handle holds; nothing for any other kind.
define internal void @h_drop_list(i64 %h) {
entry:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %list = icmp eq i64 %k, 1
  br i1 %list, label %drop, label %done
drop:
  %lp = getelementptr [64 x i64], ptr @h_list, i64 0, i64 %h
  %l = load i64, ptr %lp
  store i64 0, ptr %lp
  call void @l0_dec(i64 %l)
  br label %done
done:
  ret void
}

; A handle reading the elements of l, spec section 6.3. It keeps a reference
; to l of its own until closed.
define i64 @l0_open_bytes(i64 %l) {
entry:
  %h = call i64 @free_handle()
  %none = icmp slt i64 %h, 0
  br i1 %none, label %fail, label %ok
fail:
  ret i64 -5
ok:
  call void @h_set(i64 %h, i64 0, i64 1, ptr null)
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  store i64 1, ptr %kp
  call void @l0_inc(i64 %l)
  %lp = getelementptr [64 x i64], ptr @h_list, i64 0, i64 %h
  store i64 %l, ptr %lp
  %pp = getelementptr [64 x i64], ptr @h_pos, i64 0, i64 %h
  store i64 %l, ptr %pp
  ret i64 %h
}

define i64 @l0_open_buffer() {
entry:
  %h = call i64 @free_handle()
  %none = icmp slt i64 %h, 0
  br i1 %none, label %fail, label %alloc
alloc:
  %b = call ptr @host_alloc(i64 4096)
  %nob = icmp eq ptr %b, null
  br i1 %nob, label %fail, label %ok
fail:
  ret i64 -5
ok:
  call void @h_set(i64 %h, i64 0, i64 2, ptr %b)
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  store i64 2, ptr %kp
  %cp = getelementptr [64 x i64], ptr @h_cap, i64 0, i64 %h
  store i64 4096, ptr %cp
  ret i64 %h
}

; Everything written to a buffer, as a new list built from the last byte
; back, or the empty list for anything else.
define i64 @l0_buffer_bytes(i64 %h) {
entry:
  %w = call i1 @h_is(i64 %h, i64 2)
  br i1 %w, label %kind, label %empty
kind:
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %buffer = icmp eq i64 %k, 2
  br i1 %buffer, label %build, label %empty
build:
  %lp = getelementptr [64 x i64], ptr @h_len, i64 0, i64 %h
  %n = load i64, ptr %lp
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %buf = load ptr, ptr %bp
  br label %loop
loop:
  %i = phi i64 [ %n, %build ], [ %i1, %cons ]
  %acc = phi i64 [ 0, %build ], [ %acc1, %cons ]
  %done = icmp eq i64 %i, 0
  br i1 %done, label %out, label %cons
cons:
  %i1 = sub i64 %i, 1
  %cp = getelementptr i8, ptr %buf, i64 %i1
  %c = load i8, ptr %cp
  %v = zext i8 %c to i64
  %acc1 = call i64 @l0_new_cons(i64 %v, i64 %acc, i64 2)
  br label %loop
out:
  ret i64 %acc
empty:
  ret i64 0
}

; At a normal exit, before the counting is checked: the lists that list
; handles still hold are released, as if every handle were closed.
define internal void @release_lists() {
entry:
  br label %loop
loop:
  %h = phi i64 [ 3, %entry ], [ %h1, %next ]
  %end = icmp eq i64 %h, 64
  br i1 %end, label %done, label %body
body:
  %r = call i1 @h_is(i64 %h, i64 1)
  br i1 %r, label %drop, label %next
drop:
  call void @h_drop_list(i64 %h)
  br label %next
next:
  %h1 = add i64 %h, 1
  br label %loop
done:
  ret void
}

define i64 @l0_write_byte(i64 %v) {
entry:
  %r = call i64 @l0_write_to(i64 1, i64 %v)
  ret i64 %r
}

define i64 @l0_close(i64 %h) {
entry:
  %std = icmp slt i64 %h, 3
  br i1 %std, label %bad, label %chk
chk:
  %r = call i1 @h_is(i64 %h, i64 1)
  %w = call i1 @h_is(i64 %h, i64 2)
  %open = or i1 %r, %w
  br i1 %open, label %go, label %bad
bad:
  ret i64 -2
go:
  br i1 %w, label %flush, label %shut
flush:
  %fr = call i64 @h_flush(i64 %h)
  br label %shut
shut:
  %res = phi i64 [ 0, %go ], [ %fr, %flush ]
  %kp = getelementptr [64 x i64], ptr @h_kind, i64 0, i64 %h
  %k = load i64, ptr %kp
  %isfd = icmp eq i64 %k, 0
  br i1 %isfd, label %shutfd, label %memory
shutfd:
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  %fd = load i64, ptr %fp
  %cfd = call i64 @l0_host_close(i64 %fd)
  br label %release
memory:
  call void @h_drop_list(i64 %h)
  br label %release
release:
  %cw = phi i64 [ %cfd, %shutfd ], [ 0, %memory ]
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %buf = load ptr, ptr %bp
  call void @l0_host_free(ptr %buf)
  %mp = getelementptr [64 x i64], ptr @h_mode, i64 0, i64 %h
  store i64 0, ptr %mp
  %cfail = icmp ne i64 %cw, 0
  %earlier = icmp ne i64 %res, 0
  %closed = select i1 %earlier, i64 %res, i64 %cw
  %final = select i1 %cfail, i64 %closed, i64 %res
  ret i64 %final
}

; ------------------------------------------------------------------- files

; An L0 list as a NUL-terminated C string from malloc, or null if it holds a
; zero byte or memory ran out.
define internal ptr @to_cstr(i64 %l) {
entry:
  br label %count
count:
  %c = phi i64 [ %l, %entry ], [ %cn, %cstep ]
  %n = phi i64 [ 0, %entry ], [ %n1, %cstep ]
  %cend = icmp eq i64 %c, 0
  br i1 %cend, label %alloc, label %cstep
cstep:
  %cq = inttoptr i64 %c to ptr
  %cnp = getelementptr i64, ptr %cq, i64 1
  %cn = load i64, ptr %cnp
  %n1 = add i64 %n, 1
  br label %count
alloc:
  %sz = add i64 %n, 1
  %s = call ptr @host_alloc(i64 %sz)
  %null = icmp eq ptr %s, null
  br i1 %null, label %fail, label %copy
copy:
  %d = phi i64 [ %l, %alloc ], [ %dn, %store ]
  %i = phi i64 [ 0, %alloc ], [ %i1, %store ]
  %dend = icmp eq i64 %d, 0
  br i1 %dend, label %term, label %elem
elem:
  %dq = inttoptr i64 %d to ptr
  %v = load i64, ptr %dq
  %b = trunc i64 %v to i8
  %zb = icmp eq i8 %b, 0
  br i1 %zb, label %zero, label %store
store:
  %sp = getelementptr i8, ptr %s, i64 %i
  store i8 %b, ptr %sp
  %i1 = add i64 %i, 1
  %dnp = getelementptr i64, ptr %dq, i64 1
  %dn = load i64, ptr %dnp
  br label %copy
zero:
  call void @l0_host_free(ptr %s)
  br label %fail
term:
  %tp = getelementptr i8, ptr %s, i64 %i
  store i8 0, ptr %tp
  ret ptr %s
fail:
  ret ptr null
}

define internal i64 @free_handle() {
entry:
  br label %loop
loop:
  %h = phi i64 [ 3, %entry ], [ %h1, %next ]
  %end = icmp eq i64 %h, 64
  br i1 %end, label %none, label %body
body:
  %mp = getelementptr [64 x i64], ptr @h_mode, i64 0, i64 %h
  %m = load i64, ptr %mp
  %free = icmp eq i64 %m, 0
  br i1 %free, label %found, label %next
next:
  %h1 = add i64 %h, 1
  br label %loop
found:
  ret i64 %h
none:
  ret i64 -1
}

; mode 1 opens for reading, 2 creates or empties for writing, and 3 opens
; for writing at the end, as l0_host_open does. The results are spec section
; 6.3's: a handle, the host's code, or -5 if the path holds a zero byte or
; no handle or buffer can be had.
define internal i64 @open_handle(i64 %path, i64 %mode) {
entry:
  %rd = icmp eq i64 %mode, 1
  %s = call ptr @to_cstr(i64 %path)
  %nos = icmp eq ptr %s, null
  br i1 %nos, label %other, label %slot
slot:
  %h = call i64 @free_handle()
  %noh = icmp slt i64 %h, 0
  br i1 %noh, label %other_free, label %buf
buf:
  %b = call ptr @host_alloc(i64 65536)
  %nob = icmp eq ptr %b, null
  br i1 %nob, label %other_free, label %open
open:
  %fd = call i64 @l0_host_open(ptr %s, i64 %mode)
  call void @l0_host_free(ptr %s)
  %failed = icmp slt i64 %fd, 0
  br i1 %failed, label %refused, label %ok
ok:
  %hmode = select i1 %rd, i64 1, i64 2
  call void @h_set(i64 %h, i64 %fd, i64 %hmode, ptr %b)
  ret i64 %h
refused:
  call void @l0_host_free(ptr %b)
  ret i64 %fd
other_free:
  call void @l0_host_free(ptr %s)
  br label %other
other:
  ret i64 -5
}

define i64 @l0_open_read(i64 %path) {
entry:
  %h = call i64 @open_handle(i64 %path, i64 1)
  ret i64 %h
}

define i64 @l0_open_write(i64 %path) {
entry:
  %h = call i64 @open_handle(i64 %path, i64 2)
  ret i64 %h
}

define i64 @l0_open_append(i64 %path) {
entry:
  %h = call i64 @open_handle(i64 %path, i64 3)
  ret i64 %h
}

; The host replaces to in one step, as spec section 6.3 requires, and says
; why when it cannot.
define i64 @l0_rename(i64 %from, i64 %to) {
entry:
  %a = call ptr @to_cstr(i64 %from)
  %b = call ptr @to_cstr(i64 %to)
  %na = icmp eq ptr %a, null
  %nb = icmp eq ptr %b, null
  %either = or i1 %na, %nb
  br i1 %either, label %bad, label %go
bad:
  call void @l0_host_free(ptr %a)
  call void @l0_host_free(ptr %b)
  ret i64 -5
go:
  %r = call i64 @l0_host_rename(ptr %a, ptr %b)
  call void @l0_host_free(ptr %a)
  call void @l0_host_free(ptr %b)
  ret i64 %r
}

define i64 @l0_remove(i64 %path) {
entry:
  %s = call ptr @to_cstr(i64 %path)
  %nos = icmp eq ptr %s, null
  br i1 %nos, label %bad, label %go
bad:
  ret i64 -5
go:
  %r = call i64 @l0_host_remove(ptr %s)
  call void @l0_host_free(ptr %s)
  ret i64 %r
}

; --------------------------------------------------------------- arguments

define i64 @l0_arg_count() {
entry:
  %n = call i64 @l0_host_arg_count()
  ret i64 %n
}

define i64 @l0_arg(i64 %i) {
entry:
  %count = call i64 @l0_arg_count()
  %lo = icmp sge i64 %i, 0
  %hi = icmp slt i64 %i, %count
  %in = and i1 %lo, %hi
  br i1 %in, label %get, label %none
none:
  ret i64 0
get:
  %s = call ptr @l0_host_arg(i64 %i)
  br label %len
len:
  %n = phi i64 [ 0, %get ], [ %n1, %lstep ]
  %cp = getelementptr i8, ptr %s, i64 %n
  %c = load i8, ptr %cp
  %z = icmp eq i8 %c, 0
  br i1 %z, label %bl, label %lstep
lstep:
  %n1 = add i64 %n, 1
  br label %len
bl:
  %k = phi i64 [ %n, %len ], [ %k1, %bstep ]
  %acc = phi i64 [ 0, %len ], [ %acc1, %bstep ]
  %more = icmp sgt i64 %k, 0
  br i1 %more, label %bstep, label %done
bstep:
  %k1 = sub i64 %k, 1
  %bp = getelementptr i8, ptr %s, i64 %k1
  %b = load i8, ptr %bp
  %bv = zext i8 %b to i64
  %acc1 = call i64 @l0_new_cons(i64 %bv, i64 %acc, i64 2)
  br label %bl
done:
  ret i64 %acc
}

; ------------------------------------------------------------------- clock

; Spec section 6.7.
define i64 @l0_clock_ns() {
entry:
  %t = call i64 @l0_host_clock_ns()
  ret i64 %t
}

; ----------------------------------------------------------------- machine

; Spec section 6.16.
define i64 @l0_machine() {
entry:
  %m = call i64 @l0_host_machine()
  ret i64 %m
}

; Spec section 6.12: the board starts again, or -3.
define i64 @l0_board_reset() {
entry:
  %r = call i64 @l0_host_board_reset()
  ret i64 %r
}

; ----------------------------------------------------------------- regions

; The regions of spec section 6.12 a program has open: for each, the
; address the host gave for its first byte, and its length. A region is an
; index into them, and a length of 0, which no open region has, is a slot
; that is free.
@rg_addr = internal global [64 x i64] zeroinitializer
@rg_len = internal global [64 x i64] zeroinitializer

@m_region = private constant [12 x i8] c"not a region"
@m_rrange = private constant [26 x i8] c"region offset out of range"
@m_ralign = private constant [24 x i8] c"misaligned region access"

define i64 @l0_region_open(i64 %base, i64 %len) {
entry:
  %short = icmp slt i64 %len, 1
  %neg = icmp slt i64 %base, 0
  %bad = or i1 %short, %neg
  br i1 %bad, label %none, label %ask
ask:
  %a = call i64 @l0_host_region(i64 %base, i64 %len)
  %failed = icmp slt i64 %a, 0
  br i1 %failed, label %refused, label %find
refused:
  ret i64 %a
find:
  %n = phi i64 [ 0, %ask ], [ %n1, %taken ]
  %full = icmp uge i64 %n, 64
  br i1 %full, label %nomore, label %look
look:
  %lp = getelementptr [64 x i64], ptr @rg_len, i64 0, i64 %n
  %l = load i64, ptr %lp
  %free = icmp eq i64 %l, 0
  br i1 %free, label %keep, label %taken
taken:
  %n1 = add i64 %n, 1
  br label %find
nomore:
  ; The host gave the region; it is handed back, since none can hold it.
  call void @l0_host_region_close(i64 %a, i64 %len)
  ret i64 -5
keep:
  %ap = getelementptr [64 x i64], ptr @rg_addr, i64 0, i64 %n
  store i64 %a, ptr %ap
  store i64 %len, ptr %lp
  ret i64 %n
none:
  ret i64 -3
}

; Where region r's length is kept, if r is open, or the runtime error.
define internal ptr @region_slot(i64 %r) {
entry:
  %in = icmp ult i64 %r, 64
  br i1 %in, label %look, label %notopen
look:
  %lp = getelementptr [64 x i64], ptr @rg_len, i64 0, i64 %r
  %len = load i64, ptr %lp
  %free = icmp eq i64 %len, 0
  br i1 %free, label %notopen, label %open
open:
  ret ptr %lp
notopen:
  call void @rt_error(ptr @m_region, i64 12)
  unreachable
}

; Spec section 6.12: the accesses made are complete, then the host undoes
; what it did, and the slot is free.
define i64 @l0_region_close(i64 %r) {
entry:
  %lp = call ptr @region_slot(i64 %r)
  %len = load i64, ptr %lp
  %ap = getelementptr [64 x i64], ptr @rg_addr, i64 0, i64 %r
  %a = load i64, ptr %ap
  call void @l0_host_barrier()
  call void @l0_host_region_close(i64 %a, i64 %len)
  store i64 0, ptr %lp
  ret i64 0
}

; The address of an access of w bytes at off in region r, after the three
; checks of spec section 6.12, in its order.
define internal ptr @region_at(i64 %r, i64 %off, i64 %w) {
entry:
  %lp = call ptr @region_slot(i64 %r)
  %len = load i64, ptr %lp
  %neg = icmp slt i64 %off, 0
  %room = sub i64 %len, %w
  %past = icmp sgt i64 %off, %room
  %out = or i1 %neg, %past
  br i1 %out, label %outside, label %align
outside:
  call void @rt_error(ptr @m_rrange, i64 26)
  unreachable
align:
  %ap = getelementptr [64 x i64], ptr @rg_addr, i64 0, i64 %r
  %base = load i64, ptr %ap
  %at = add i64 %base, %off
  %w1 = sub i64 %w, 1
  %odd = and i64 %at, %w1
  %mis = icmp ne i64 %odd, 0
  br i1 %mis, label %misaligned, label %ok
misaligned:
  call void @rt_error(ptr @m_ralign, i64 24)
  unreachable
ok:
  %p = inttoptr i64 %at to ptr
  ret ptr %p
}

define i64 @l0_region_read8(i64 %r, i64 %off) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 1)
  %v = load volatile i8, ptr %p, align 1
  %x = zext i8 %v to i64
  ret i64 %x
}

define i64 @l0_region_read16(i64 %r, i64 %off) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 2)
  %v = load volatile i16, ptr %p, align 2
  %x = zext i16 %v to i64
  ret i64 %x
}

define i64 @l0_region_read32(i64 %r, i64 %off) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 4)
  %v = load volatile i32, ptr %p, align 4
  %x = zext i32 %v to i64
  ret i64 %x
}

define i64 @l0_region_read64(i64 %r, i64 %off) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 8)
  %v = load volatile i64, ptr %p, align 8
  ret i64 %v
}

define i64 @l0_region_write8(i64 %r, i64 %off, i64 %v) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 1)
  %t = trunc i64 %v to i8
  store volatile i8 %t, ptr %p, align 1
  ret i64 0
}

define i64 @l0_region_write16(i64 %r, i64 %off, i64 %v) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 2)
  %t = trunc i64 %v to i16
  store volatile i16 %t, ptr %p, align 2
  ret i64 0
}

define i64 @l0_region_write32(i64 %r, i64 %off, i64 %v) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 4)
  %t = trunc i64 %v to i32
  store volatile i32 %t, ptr %p, align 4
  ret i64 0
}

define i64 @l0_region_write64(i64 %r, i64 %off, i64 %v) {
entry:
  %p = call ptr @region_at(i64 %r, i64 %off, i64 8)
  store volatile i64 %v, ptr %p, align 8
  ret i64 0
}

; The address n bytes at off in region r start at, once region_slot has
; said r is open: the offset check of spec section 6.12, with no alignment.
define internal ptr @region_span(i64 %r, i64 %off, i64 %n) {
entry:
  %lp = getelementptr [64 x i64], ptr @rg_len, i64 0, i64 %r
  %len = load i64, ptr %lp
  %neg = icmp slt i64 %off, 0
  %room = sub i64 %len, %n
  %past = icmp sgt i64 %off, %room
  %out = or i1 %neg, %past
  br i1 %out, label %outside, label %ok
outside:
  call void @rt_error(ptr @m_rrange, i64 26)
  unreachable
ok:
  %ap = getelementptr [64 x i64], ptr @rg_addr, i64 0, i64 %r
  %base = load i64, ptr %ap
  %at = add i64 %base, %off
  %p = inttoptr i64 %at to ptr
  ret ptr %p
}

; A byte at a time, each region access volatile: no wider or unaligned
; access reaches memory a host may map as a device's, and the loop is never
; made a call to memcpy, which a host without libc may not have.
define i64 @l0_region_read_bytes(i64 %r, i64 %off, i64 %n) {
entry:
  %lp = call ptr @region_slot(i64 %r)
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %err, label %span
err:
  call void @rt_error(ptr @m_bcount, i64 23)
  unreachable
span:
  %src = call ptr @region_span(i64 %r, i64 %off, i64 %n)
  %b = call i64 @bytes_alloc(i64 %n)
  %bi = add i64 %b, 8
  %dst = inttoptr i64 %bi to ptr
  br label %loop
loop:
  %k = phi i64 [ 0, %span ], [ %k1, %copy ]
  %done = icmp eq i64 %k, %n
  br i1 %done, label %out, label %copy
copy:
  %sp = getelementptr i8, ptr %src, i64 %k
  %v = load volatile i8, ptr %sp, align 1
  %dp = getelementptr i8, ptr %dst, i64 %k
  store i8 %v, ptr %dp, align 1
  %k1 = add i64 %k, 1
  br label %loop
out:
  ret i64 %b
}

; b is read, not consumed, as write_bytes reads its bytes.
define i64 @l0_region_write_bytes(i64 %r, i64 %off, i64 %b, i64 %i, i64 %j) {
entry:
  %lp = call ptr @region_slot(i64 %r)
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  %lo = icmp ule i64 %i, %j
  %hi = icmp ule i64 %j, %n
  %in = and i1 %lo, %hi
  br i1 %in, label %span, label %err
err:
  call void @rt_error(ptr @m_brange, i64 23)
  unreachable
span:
  %len = sub i64 %j, %i
  %dst = call ptr @region_span(i64 %r, i64 %off, i64 %len)
  %o = add i64 %i, 8
  %src = getelementptr i8, ptr %q, i64 %o
  br label %loop
loop:
  %k = phi i64 [ 0, %span ], [ %k1, %copy ]
  %done = icmp eq i64 %k, %len
  br i1 %done, label %out, label %copy
copy:
  %sp = getelementptr i8, ptr %src, i64 %k
  %v = load i8, ptr %sp, align 1
  %dp = getelementptr i8, ptr %dst, i64 %k
  store volatile i8 %v, ptr %dp, align 1
  %k1 = add i64 %k, 1
  br label %loop
out:
  ret i64 0
}

define i64 @l0_barrier() {
entry:
  call void @l0_host_barrier()
  ret i64 0
}

; --------------------------------------------------------------- user mode
;
; Spec section 6.13. The host keeps the spaces and frames and checks them,
; in the section's order, and answers with 0 or a code (section 10.3); a
; positive code is the runtime error raised here.

@m_space = private constant [11 x i8] c"not a space"
@m_frame = private constant [11 x i8] c"not a frame"
@m_perm = private constant [29 x i8] c"page permissions out of range"
@m_upage = private constant [15 x i8] c"not a user page"
@m_umapped = private constant [24 x i8] c"user page already mapped"
@m_unmapped = private constant [22 x i8] c"user memory not mapped"
@m_context = private constant [13 x i8] c"not a context"
@m_taken = private constant [19 x i8] c"interrupt not taken"
@m_still = private constant [18 x i8] c"frame still mapped"
@m_notmapped = private constant [20 x i8] c"user page not mapped"
@m_notcpu = private constant [9 x i8] c"not a CPU"
@m_running = private constant [19 x i8] c"space still running"

define internal void @user_check(i64 %k) {
entry:
  switch i64 %k, label %ok [ i64 1, label %space
                             i64 2, label %frame
                             i64 3, label %perm
                             i64 4, label %upage
                             i64 5, label %mapped
                             i64 6, label %unmapped
                             i64 7, label %context
                             i64 8, label %taken
                             i64 9, label %still
                             i64 10, label %notmapped
                             i64 11, label %notcpu
                             i64 12, label %running ]
space:
  call void @rt_error(ptr @m_space, i64 11)
  unreachable
frame:
  call void @rt_error(ptr @m_frame, i64 11)
  unreachable
perm:
  call void @rt_error(ptr @m_perm, i64 29)
  unreachable
upage:
  call void @rt_error(ptr @m_upage, i64 15)
  unreachable
mapped:
  call void @rt_error(ptr @m_umapped, i64 24)
  unreachable
unmapped:
  call void @rt_error(ptr @m_unmapped, i64 22)
  unreachable
context:
  call void @rt_error(ptr @m_context, i64 13)
  unreachable
taken:
  call void @rt_error(ptr @m_taken, i64 19)
  unreachable
still:
  call void @rt_error(ptr @m_still, i64 18)
  unreachable
notmapped:
  call void @rt_error(ptr @m_notmapped, i64 20)
  unreachable
notcpu:
  call void @rt_error(ptr @m_notcpu, i64 9)
  unreachable
running:
  call void @rt_error(ptr @m_running, i64 19)
  unreachable
ok:
  ret void
}

define i64 @l0_space_new() {
entry:
  %r = call i64 @l0_host_space_new()
  ret i64 %r
}

define i64 @l0_frame_new() {
entry:
  %r = call i64 @l0_host_frame_new()
  ret i64 %r
}

; The pages left, or -3.
define i64 @l0_frame_free_count() {
entry:
  %r = call i64 @l0_host_frame_free_count()
  ret i64 %r
}

; Spec section 6.19: what the host's heap has free, and what the runtime
; could give again without asking it, the free lists, the current chunk's
; uncut rest, and the chunks kept; it never sweeps.
define i64 @l0_heap_left() {
entry:
  %h = call i64 @l0_host_heap_left()
  %none = icmp slt i64 %h, 0
  br i1 %none, label %out, label %count
count:
  %fb = load i64, ptr @free_bytes
  %cur = load i64, ptr @chunk_cur
  %end = load i64, ptr @chunk_end
  %uncut = sub i64 %end, %cur
  %ec = load i64, ptr @empty_count
  %kept = mul i64 %ec, 1048512
  %a = add i64 %h, %fb
  %b = add i64 %a, %uncut
  %c = add i64 %b, %kept
  ret i64 %c
out:
  ret i64 %h
}

; The address, a multiple of 4096 and so never a code, or -3, or 2, not a
; frame.
define i64 @l0_frame_address(i64 %f) {
entry:
  %k = call i64 @l0_host_frame_address(i64 %f)
  call void @user_check(i64 %k)
  ret i64 %k
}

@m_sdir = private constant [27 x i8] c"sync direction out of range"

; 0, or a runtime error: whether f is a frame, as frame_address says, and
; then dir, spec section 6.13's order.
define i64 @l0_frame_sync(i64 %f, i64 %dir) {
entry:
  %a = call i64 @l0_host_frame_address(i64 %f)
  call void @user_check(i64 %a)
  %lo = icmp slt i64 %dir, 1
  %hi = icmp sgt i64 %dir, 3
  %bad = or i1 %lo, %hi
  br i1 %bad, label %err, label %sync
err:
  call void @rt_error(ptr @m_sdir, i64 27)
  unreachable
sync:
  %k = call i64 @l0_host_frame_sync(i64 %f, i64 %dir)
  call void @user_check(i64 %k)
  ret i64 0
}

; 0, or -5 when the host has no room left for the tables.
define i64 @l0_space_map(i64 %s, i64 %va, i64 %f, i64 %perm) {
entry:
  %k = call i64 @l0_host_space_map(i64 %s, i64 %va, i64 %f, i64 %perm)
  call void @user_check(i64 %k)
  %none = icmp slt i64 %k, 0
  %r = select i1 %none, i64 %k, i64 0
  ret i64 %r
}

; 0, or a runtime error: spec section 6.13.
define i64 @l0_space_unmap(i64 %s, i64 %va) {
entry:
  %k = call i64 @l0_host_space_unmap(i64 %s, i64 %va)
  call void @user_check(i64 %k)
  ret i64 0
}

define i64 @l0_space_free(i64 %s) {
entry:
  %k = call i64 @l0_host_space_free(i64 %s)
  call void @user_check(i64 %k)
  ret i64 0
}

define i64 @l0_frame_free(i64 %f) {
entry:
  %k = call i64 @l0_host_frame_free(i64 %f)
  call void @user_check(i64 %k)
  ret i64 0
}

; 0, or -3 when the host gives no region over the range, or -5 as for
; l0_space_map.
define i64 @l0_space_map_device(i64 %s, i64 %va, i64 %base, i64 %len) {
entry:
  %k = call i64 @l0_host_space_map_device(i64 %s, i64 %va, i64 %base, i64 %len)
  call void @user_check(i64 %k)
  %none = icmp slt i64 %k, 0
  %r = select i1 %none, i64 %k, i64 0
  ret i64 %r
}

; An empty copy, which says only whether s is a space, comes first, so
; that a bad count or range is reported after a bad space, as section 6.13
; orders them.
define i64 @l0_space_read(i64 %s, i64 %va, i64 %n) {
entry:
  %k0 = call i64 @l0_host_space_copy(i64 %s, i64 %va, ptr null, i64 0, i64 0)
  call void @user_check(i64 %k0)
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %err, label %copy
err:
  call void @rt_error(ptr @m_bcount, i64 23)
  unreachable
copy:
  %b = call i64 @bytes_alloc(i64 %n)
  %bi = add i64 %b, 8
  %bp = inttoptr i64 %bi to ptr
  %k = call i64 @l0_host_space_copy(i64 %s, i64 %va, ptr %bp, i64 %n, i64 0)
  call void @user_check(i64 %k)
  ret i64 %b
}

; b is read, not consumed, as write_bytes reads its bytes.
define i64 @l0_space_write(i64 %s, i64 %va, i64 %b, i64 %i, i64 %j) {
entry:
  %k0 = call i64 @l0_host_space_copy(i64 %s, i64 %va, ptr null, i64 0, i64 1)
  call void @user_check(i64 %k0)
  %q = inttoptr i64 %b to ptr
  %n = load i64, ptr %q
  %lo = icmp ule i64 %i, %j
  %hi = icmp ule i64 %j, %n
  %in = and i1 %lo, %hi
  br i1 %in, label %copy, label %err
err:
  call void @rt_error(ptr @m_brange, i64 23)
  unreachable
copy:
  %o = add i64 %i, 8
  %src = getelementptr i8, ptr %q, i64 %o
  %len = sub i64 %j, %i
  %k = call i64 @l0_host_space_copy(i64 %s, i64 %va, ptr %src, i64 %len, i64 1)
  call void @user_check(i64 %k)
  ret i64 0
}

; c is consumed, as array_set's array is: the thread runs on c itself when
; nothing else holds it, and on a copy otherwise, which is returned.
define i64 @l0_user_run(i64 %s, i64 %c) {
entry:
  %c1 = call i64 @arr_own(i64 %c)
  %q = inttoptr i64 %c1 to ptr
  %n = load i64, ptr %q
  %w = getelementptr i64, ptr %q, i64 1
  %k = call i64 @l0_host_user_run(i64 %s, ptr %w, i64 %n)
  call void @user_check(i64 %k)
  ret i64 %c1
}

; ---------------------------------------------------------------- other CPUs
;
; Spec section 6.18. The host keeps the CPUs and their rings; a context is
; copied into a ring and back out, so no value of the program's is ever on
; another CPU.

define i64 @l0_cpu_count() {
entry:
  %r = call i64 @l0_host_cpu_count()
  ret i64 %r
}

; c is read, not consumed: the host copies its words. 0 or -5.
define i64 @l0_cpu_run(i64 %c, i64 %s, i64 %ctx, i64 %deadline, i64 %tag) {
entry:
  %q = inttoptr i64 %ctx to ptr
  %n = load i64, ptr %q
  %w = getelementptr i64, ptr %q, i64 1
  %k = call i64 @l0_host_cpu_run(i64 %c, i64 %s, ptr %w, i64 %n, i64 %deadline, i64 %tag)
  call void @user_check(i64 %k)
  ret i64 %k
}

; The next thread another CPU gives back, its context and then its CPU and
; tag, or an empty array; the array is built only for a thread there is.
; Every host with other CPUs has user mode, whose contexts are 104 words.
define i64 @l0_cpu_trapped() {
entry:
  %any = call i64 @l0_host_cpu_trapped(ptr null)
  %none = icmp eq i64 %any, 0
  br i1 %none, label %empty, label %take
empty:
  %e = call i64 @arr_alloc(i64 0, i64 0)
  ret i64 %e
take:
  %a = call i64 @arr_alloc(i64 106, i64 0)
  %q = inttoptr i64 %a to ptr
  %w = getelementptr i64, ptr %q, i64 1
  %got = call i64 @l0_host_cpu_trapped(ptr %w)
  ret i64 %a
}

define i64 @l0_cpu_wait() {
entry:
  call void @flush_std()
  %r = call i64 @l0_host_cpu_wait()
  ret i64 %r
}

; -------------------------------------------------------------- interrupts
;
; Spec section 6.14. The host takes and ends interrupts and keeps which are
; taken; interrupt_done's code 8 is its runtime error.

define i64 @l0_timer_at(i64 %t) {
entry:
  %r = call i64 @l0_host_timer_at(i64 %t)
  ret i64 %r
}

define i64 @l0_interrupt_enable(i64 %n) {
entry:
  %r = call i64 @l0_host_interrupt_enable(i64 %n)
  ret i64 %r
}

define i64 @l0_interrupt_wait() {
entry:
  call void @flush_std()
  %r = call i64 @l0_host_interrupt_wait()
  ret i64 %r
}

define i64 @l0_interrupt_done(i64 %n) {
entry:
  %k = call i64 @l0_host_interrupt_done(i64 %n)
  call void @user_check(i64 %k)
  ret i64 0
}

; ------------------------------------------------------- calls to a kernel
;
; Spec section 6.15. The numbers below 256 are the runtime's own calls,
; spec section 10.3, refused here on every host; bytes go to the kernel as
; the address of their first byte and their count.

@m_reserved = private constant [20 x i8] c"system call reserved"

define internal void @call_check(i64 %n) {
entry:
  %low = icmp slt i64 %n, 256
  br i1 %low, label %err, label %ok
err:
  call void @rt_error(ptr @m_reserved, i64 20)
  unreachable
ok:
  ret void
}

define i64 @l0_supervisor_call(i64 %n, i64 %a, i64 %b, i64 %c) {
entry:
  call void @call_check(i64 %n)
  %r = call i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %b, i64 %c)
  ret i64 %r
}

; b is read, not consumed, as write_bytes reads its bytes.
define i64 @l0_supervisor_send(i64 %n, i64 %a, i64 %b, i64 %i, i64 %j) {
entry:
  call void @call_check(i64 %n)
  %q = inttoptr i64 %b to ptr
  %len = load i64, ptr %q
  %lo = icmp ule i64 %i, %j
  %hi = icmp ule i64 %j, %len
  %in = and i1 %lo, %hi
  br i1 %in, label %send, label %err
err:
  call void @rt_error(ptr @m_brange, i64 23)
  unreachable
send:
  %o = add i64 %i, 8
  %at = add i64 %b, %o
  %k = sub i64 %j, %i
  %r = call i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %at, i64 %k)
  ret i64 %r
}

; Room for max bytes, of which the kernel's word says how many it wrote:
; never more than max, and none if it is negative.
define i64 @l0_supervisor_receive(i64 %n, i64 %a, i64 %max) {
entry:
  call void @call_check(i64 %n)
  %neg = icmp slt i64 %max, 0
  br i1 %neg, label %err, label %go
err:
  call void @rt_error(ptr @m_bcount, i64 23)
  unreachable
go:
  %b = call i64 @bytes_alloc(i64 %max)
  %at = add i64 %b, 8
  %r = call i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %at, i64 %max)
  %none = icmp slt i64 %r, 0
  %r0 = select i1 %none, i64 0, i64 %r
  %over = icmp ugt i64 %r0, %max
  %k = select i1 %over, i64 %max, i64 %r0
  %q = inttoptr i64 %b to ptr
  store i64 %k, ptr %q
  ret i64 %b
}

; ---------------------------------------------------------------- equality

; Pairs of blocks @l0_equal has still to compare, so comparing a long list
; or a deep nesting needs no recursion. Two words a pair.
@eq_wl = internal global ptr null
@eq_len = internal global i64 0
@eq_cap = internal global i64 0

define internal void @eq_push(i64 %a, i64 %b) {
entry:
  %n = load i64, ptr @eq_len
  %cap = load i64, ptr @eq_cap
  %full = icmp eq i64 %n, %cap
  br i1 %full, label %grow, label %put
grow:
  %none = icmp eq i64 %cap, 0
  %c2 = mul i64 %cap, 2
  %c3 = select i1 %none, i64 256, i64 %c2
  %bytes = mul i64 %c3, 16
  %old = load ptr, ptr @eq_wl
  %new = call ptr @host_resize(ptr %old, i64 %bytes)
  %bad = icmp eq ptr %new, null
  br i1 %bad, label %oom, label %grown
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
grown:
  store ptr %new, ptr @eq_wl
  store i64 %c3, ptr @eq_cap
  br label %put
put:
  %arr = load ptr, ptr @eq_wl
  %i = mul i64 %n, 2
  %ap = getelementptr i64, ptr %arr, i64 %i
  store i64 %a, ptr %ap
  %bp = getelementptr i64, ptr %ap, i64 1
  store i64 %b, ptr %bp
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @eq_len
  ret void
}

; Spec sections 6.8 and 10.3: whether the counted values a and b, of one
; type, are the same, from their blocks alone. The same block, or two empty
; lists, are the same at once. Otherwise both must be blocks of one size and
; mask; an array or bytes compares its length and then its elements, and a
; cons cell or data block its words, the words the mask marks as pointers by
; queueing the pair. Words are queued last first, so a list's element is
; compared before its rest and the queue stays as deep as the nesting, not
; as long as the list.
define i64 @l0_equal(i64 %a, i64 %b) {
entry:
  store i64 0, ptr @eq_len
  br label %pair
pair:
  %x = phi i64 [ %a, %entry ], [ %px, %pop ]
  %y = phi i64 [ %b, %entry ], [ %py, %pop ]
  %same = icmp eq i64 %x, %y
  br i1 %same, label %next, label %differ
next:
  %n = load i64, ptr @eq_len
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %yes, label %pop
pop:
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr @eq_len
  %wl = load ptr, ptr @eq_wl
  %pi = mul i64 %n1, 2
  %pxp = getelementptr i64, ptr %wl, i64 %pi
  %px = load i64, ptr %pxp
  %pyp = getelementptr i64, ptr %pxp, i64 1
  %py = load i64, ptr %pyp
  br label %pair
yes:
  ret i64 1
no:
  ret i64 0
differ:
  %xz = icmp eq i64 %x, 0
  %yz = icmp eq i64 %y, 0
  %oneempty = or i1 %xz, %yz
  br i1 %oneempty, label %no, label %blocks
blocks:
  %xhp = sub i64 %x, 8
  %xhq = inttoptr i64 %xhp to ptr
  %hx = load i64, ptr %xhq
  %yhp = sub i64 %y, 8
  %yhq = inttoptr i64 %yhp to ptr
  %hy = load i64, ptr %yhq
  %shx = and i64 %hx, 1099511627775
  %shy = and i64 %hy, 1099511627775
  %alike = icmp eq i64 %shx, %shy
  br i1 %alike, label %kind, label %no
kind:
  %mx = and i64 %hx, 4294967295
  %sx0 = lshr i64 %hx, 32
  %sx = and i64 %sx0, 255
  %xq = inttoptr i64 %x to ptr
  %yq = inttoptr i64 %y to ptr
  %isarr = icmp eq i64 %sx, 0
  br i1 %isarr, label %arr, label %scan
arr:
  %nx = load i64, ptr %xq
  %ny = load i64, ptr %yq
  %samelen = icmp eq i64 %nx, %ny
  br i1 %samelen, label %arr_kind, label %no
arr_kind:
  %ptrs = and i64 %mx, 1
  %hasp = icmp ne i64 %ptrs, 0
  br i1 %hasp, label %elems, label %flat
flat:
  %xe = getelementptr i64, ptr %xq, i64 1
  %ye = getelementptr i64, ptr %yq, i64 1
  %isb = and i64 %mx, 2
  %isbytes = icmp ne i64 %isb, 0
  %wbytes = mul i64 %nx, 8
  %len = select i1 %isbytes, i64 %nx, i64 %wbytes
  %c = call i32 @memcmp(ptr %xe, ptr %ye, i64 %len)
  %eqm = icmp eq i32 %c, 0
  br i1 %eqm, label %next, label %no
elems:
  %k = phi i64 [ %nx, %arr_kind ], [ %k1, %elem_next ]
  %kdone = icmp eq i64 %k, 0
  br i1 %kdone, label %next, label %elem
elem:
  %xkp = getelementptr i64, ptr %xq, i64 %k
  %xk = load i64, ptr %xkp
  %ykp = getelementptr i64, ptr %yq, i64 %k
  %yk = load i64, ptr %ykp
  %ek = icmp eq i64 %xk, %yk
  br i1 %ek, label %elem_next, label %elem_push
elem_push:
  call void @eq_push(i64 %xk, i64 %yk)
  br label %elem_next
elem_next:
  %k1 = sub i64 %k, 1
  br label %elems
scan:
  %j = phi i64 [ %sx, %kind ], [ %j1, %word_next ]
  %jdone = icmp eq i64 %j, 0
  br i1 %jdone, label %next, label %word
word:
  %w = sub i64 %j, 1
  %xwp = getelementptr i64, ptr %xq, i64 %w
  %xw = load i64, ptr %xwp
  %ywp = getelementptr i64, ptr %yq, i64 %w
  %yw = load i64, ptr %ywp
  %ew = icmp eq i64 %xw, %yw
  br i1 %ew, label %word_next, label %word_differ
word_differ:
  %bits = lshr i64 %mx, %w
  %bit = and i64 %bits, 1
  %isptr = icmp ne i64 %bit, 0
  br i1 %isptr, label %word_push, label %no
word_push:
  call void @eq_push(i64 %xw, i64 %yw)
  br label %word_next
word_next:
  %j1 = sub i64 %j, 1
  br label %scan
}

; ---------------------------------------------------------------- ordering

; Pairs @l0_compare has still to order, three words each: the two words, and
; 1 if they point at values to compare or 0 if they are compared as signed
; integers. The last pushed is taken first.
@cmp_wl = internal global ptr null
@cmp_len = internal global i64 0
@cmp_cap = internal global i64 0

define internal void @cmp_push(i64 %a, i64 %b, i64 %p) {
entry:
  %n = load i64, ptr @cmp_len
  %cap = load i64, ptr @cmp_cap
  %full = icmp eq i64 %n, %cap
  br i1 %full, label %grow, label %put
grow:
  %none = icmp eq i64 %cap, 0
  %c2 = mul i64 %cap, 2
  %c3 = select i1 %none, i64 256, i64 %c2
  %bytes = mul i64 %c3, 24
  %old = load ptr, ptr @cmp_wl
  %new = call ptr @host_resize(ptr %old, i64 %bytes)
  %bad = icmp eq ptr %new, null
  br i1 %bad, label %oom, label %grown
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
grown:
  store ptr %new, ptr @cmp_wl
  store i64 %c3, ptr @cmp_cap
  br label %put
put:
  %arr = load ptr, ptr @cmp_wl
  %i = mul i64 %n, 3
  %ap = getelementptr i64, ptr %arr, i64 %i
  store i64 %a, ptr %ap
  %bp = getelementptr i64, ptr %ap, i64 1
  store i64 %b, ptr %bp
  %pp = getelementptr i64, ptr %ap, i64 2
  store i64 %p, ptr %pp
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @cmp_len
  ret void
}

; -1, 0, or 1 as a is less than, equal to, or greater than b, signed.
define internal i64 @cmp_ints(i64 %a, i64 %b) {
entry:
  %gt = icmp sgt i64 %a, %b
  %lt = icmp slt i64 %a, %b
  %g = zext i1 %gt to i64
  %l = zext i1 %lt to i64
  %r = sub i64 %g, %l
  ret i64 %r
}

; Spec sections 6.11 and 10.3: the order of the counted values a and b, of
; one type, from their blocks alone. Both are walked together, in order: the
; pair of words on top of the worklist is taken, and either compared as
; integers, or, as values, expanded into the pairs of their blocks' words,
; queued last first so that word 0, a data block's tag or a cell's element,
; is taken next. The first pair that differs decides. An array queues its
; lengths below its elements, so they are compared only when every element
; the shorter has is the same.
define i64 @l0_compare(i64 %a, i64 %b) {
entry:
  store i64 0, ptr @cmp_len
  call void @cmp_push(i64 %a, i64 %b, i64 1)
  br label %take
take:
  %n = load i64, ptr @cmp_len
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %same, label %pop
same:
  ret i64 0
pop:
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr @cmp_len
  %wl = load ptr, ptr @cmp_wl
  %pi = mul i64 %n1, 3
  %xp = getelementptr i64, ptr %wl, i64 %pi
  %x = load i64, ptr %xp
  %yp = getelementptr i64, ptr %xp, i64 1
  %y = load i64, ptr %yp
  %fp = getelementptr i64, ptr %xp, i64 2
  %f = load i64, ptr %fp
  %eqw = icmp eq i64 %x, %y
  br i1 %eqw, label %take, label %differ
differ:
  %isval = icmp ne i64 %f, 0
  br i1 %isval, label %values, label %words
words:
  %w = call i64 @cmp_ints(i64 %x, i64 %y)
  ret i64 %w
values:
  %xz = icmp eq i64 %x, 0
  br i1 %xz, label %less, label %ynil
ynil:
  %yz = icmp eq i64 %y, 0
  br i1 %yz, label %more, label %blocks
less:
  ret i64 -1
more:
  ret i64 1
blocks:
  %xhp = sub i64 %x, 8
  %xhq = inttoptr i64 %xhp to ptr
  %hx = load i64, ptr %xhq
  %mx = and i64 %hx, 4294967295
  %sx0 = lshr i64 %hx, 32
  %sx = and i64 %sx0, 255
  %xq = inttoptr i64 %x to ptr
  %yq = inttoptr i64 %y to ptr
  %isarr = icmp eq i64 %sx, 0
  br i1 %isarr, label %arr, label %cells
cells:
  br label %cell_loop
cell_loop:
  %j = phi i64 [ %sx, %cells ], [ %j1, %cell_push ]
  %jdone = icmp eq i64 %j, 0
  br i1 %jdone, label %take, label %cell_push
cell_push:
  %j1 = sub i64 %j, 1
  %xwp = getelementptr i64, ptr %xq, i64 %j1
  %xw = load i64, ptr %xwp
  %ywp = getelementptr i64, ptr %yq, i64 %j1
  %yw = load i64, ptr %ywp
  %bits = lshr i64 %mx, %j1
  %bit = and i64 %bits, 1
  call void @cmp_push(i64 %xw, i64 %yw, i64 %bit)
  br label %cell_loop
arr:
  %nx = load i64, ptr %xq
  %ny = load i64, ptr %yq
  %short = icmp slt i64 %nx, %ny
  %m = select i1 %short, i64 %nx, i64 %ny
  %isb = and i64 %mx, 2
  %isbytes = icmp ne i64 %isb, 0
  br i1 %isbytes, label %bytes, label %arr_kind
bytes:
  %xb = getelementptr i64, ptr %xq, i64 1
  %yb = getelementptr i64, ptr %yq, i64 1
  %c = call i32 @memcmp(ptr %xb, ptr %yb, i64 %m)
  %cneg = icmp slt i32 %c, 0
  br i1 %cneg, label %less, label %bytes_pos
bytes_pos:
  %cpos = icmp sgt i32 %c, 0
  br i1 %cpos, label %more, label %by_length
by_length:
  %l = call i64 @cmp_ints(i64 %nx, i64 %ny)
  %lz = icmp eq i64 %l, 0
  br i1 %lz, label %take, label %length_differs
length_differs:
  ret i64 %l
arr_kind:
  %ptrs = and i64 %mx, 1
  %hasp = icmp ne i64 %ptrs, 0
  br i1 %hasp, label %arr_values, label %flat
flat:
  br label %flat_loop
flat_loop:
  %k = phi i64 [ 1, %flat ], [ %k1, %flat_same ]
  %kdone = icmp sgt i64 %k, %m
  br i1 %kdone, label %by_length, label %flat_elem
flat_elem:
  %xkp = getelementptr i64, ptr %xq, i64 %k
  %xk = load i64, ptr %xkp
  %ykp = getelementptr i64, ptr %yq, i64 %k
  %yk = load i64, ptr %ykp
  %ce = call i64 @cmp_ints(i64 %xk, i64 %yk)
  %cez = icmp eq i64 %ce, 0
  br i1 %cez, label %flat_same, label %flat_differs
flat_same:
  %k1 = add i64 %k, 1
  br label %flat_loop
flat_differs:
  ret i64 %ce
arr_values:
  call void @cmp_push(i64 %nx, i64 %ny, i64 0)
  br label %val_loop
val_loop:
  %v = phi i64 [ %m, %arr_values ], [ %v1, %val_push ]
  %vdone = icmp eq i64 %v, 0
  br i1 %vdone, label %take, label %val_push
val_push:
  %xvp = getelementptr i64, ptr %xq, i64 %v
  %xv = load i64, ptr %xvp
  %yvp = getelementptr i64, ptr %yq, i64 %v
  %yv = load i64, ptr %yvp
  call void @cmp_push(i64 %xv, i64 %yv, i64 1)
  %v1 = sub i64 %v, 1
  br label %val_loop
}

; ----------------------------------------------------------------- hashing

; One item into the hash at hp: spec 6.9's (h xor i) * 1099511628211.
define internal void @hash_mix(ptr %hp, i64 %i) {
entry:
  %h = load i64, ptr %hp
  %x = xor i64 %h, %i
  %m = mul i64 %x, 1099511628211
  store i64 %m, ptr %hp
  ret void
}

; Spec sections 6.9 and 10.3: the hash of x, which is a counted value when
; counted is 1. The words still to visit share @l0_equal's worklist, which no
; hash and comparison ever use at once, each entry a word and whether it is a
; pointer. A block's words are queued last first, so they are taken in order
; and a value's items come out in the order 6.9 gives them; the worklist stays
; as deep as the nesting, not as long as a list. The empty list is the word 0,
; and contributes the item 0, as any word that is not a pointer contributes
; itself.
define i64 @l0_hash(i64 %x, i64 %counted) {
entry:
  %hp = alloca i64
  store i64 -3750763034362895579, ptr %hp
  store i64 0, ptr @eq_len
  br label %visit
visit:
  %w = phi i64 [ %x, %entry ], [ %pw, %pop ]
  %p = phi i64 [ %counted, %entry ], [ %pp, %pop ]
  %isp = icmp ne i64 %p, 0
  %nz = icmp ne i64 %w, 0
  %block = and i1 %isp, %nz
  br i1 %block, label %blocks, label %word
word:
  call void @hash_mix(ptr %hp, i64 %w)
  br label %next
blocks:
  %hdp = sub i64 %w, 8
  %hdq = inttoptr i64 %hdp to ptr
  %hd = load i64, ptr %hdq
  %mx = and i64 %hd, 4294967295
  %s0 = lshr i64 %hd, 32
  %sx = and i64 %s0, 255
  %wq = inttoptr i64 %w to ptr
  %isarr = icmp eq i64 %sx, 0
  br i1 %isarr, label %arr, label %scan
arr:
  %n = load i64, ptr %wq
  call void @hash_mix(ptr %hp, i64 %n)
  %isb = and i64 %mx, 2
  %isbytes = icmp ne i64 %isb, 0
  br i1 %isbytes, label %bytes, label %arr_kind
bytes:
  %b0 = getelementptr i64, ptr %wq, i64 1
  br label %byte_loop
byte_loop:
  %bi = phi i64 [ 0, %bytes ], [ %bi1, %byte ]
  %bdone = icmp eq i64 %bi, %n
  br i1 %bdone, label %next, label %byte
byte:
  %bp = getelementptr i8, ptr %b0, i64 %bi
  %bv = load i8, ptr %bp
  %bw = zext i8 %bv to i64
  call void @hash_mix(ptr %hp, i64 %bw)
  %bi1 = add i64 %bi, 1
  br label %byte_loop
arr_kind:
  %ptrs = and i64 %mx, 1
  %hasp = icmp ne i64 %ptrs, 0
  br i1 %hasp, label %elems, label %flat
flat:
  %fi = phi i64 [ 1, %arr_kind ], [ %fi1, %flat_elem ]
  %fdone = icmp sgt i64 %fi, %n
  br i1 %fdone, label %next, label %flat_elem
flat_elem:
  %fp = getelementptr i64, ptr %wq, i64 %fi
  %fv = load i64, ptr %fp
  call void @hash_mix(ptr %hp, i64 %fv)
  %fi1 = add i64 %fi, 1
  br label %flat
elems:
  %k = phi i64 [ %n, %arr_kind ], [ %k1, %elem ]
  %kdone = icmp eq i64 %k, 0
  br i1 %kdone, label %next, label %elem
elem:
  %ep = getelementptr i64, ptr %wq, i64 %k
  %ev = load i64, ptr %ep
  call void @eq_push(i64 %ev, i64 1)
  %k1 = sub i64 %k, 1
  br label %elems
scan:
  %j = phi i64 [ %sx, %blocks ], [ %j1, %word_push ]
  %jdone = icmp eq i64 %j, 0
  br i1 %jdone, label %next, label %word_push
word_push:
  %jw = sub i64 %j, 1
  %wp = getelementptr i64, ptr %wq, i64 %jw
  %wv = load i64, ptr %wp
  %bits = lshr i64 %mx, %jw
  %bit = and i64 %bits, 1
  call void @eq_push(i64 %wv, i64 %bit)
  %j1 = sub i64 %j, 1
  br label %scan
next:
  %len = load i64, ptr @eq_len
  %empty = icmp eq i64 %len, 0
  br i1 %empty, label %done, label %pop
pop:
  %len1 = sub i64 %len, 1
  store i64 %len1, ptr @eq_len
  %wl = load ptr, ptr @eq_wl
  %pi = mul i64 %len1, 2
  %pwp = getelementptr i64, ptr %wl, i64 %pi
  %pw = load i64, ptr %pwp
  %ppp = getelementptr i64, ptr %pwp, i64 1
  %pp = load i64, ptr %ppp
  br label %visit
done:
  %h0 = load i64, ptr %hp
  %r1 = lshr i64 %h0, 30
  %x1 = xor i64 %h0, %r1
  %m1 = mul i64 %x1, -4658895280553007687
  %r2 = lshr i64 %m1, 27
  %x2 = xor i64 %m1, %r2
  %m2 = mul i64 %x2, -7723592293110705685
  %r3 = lshr i64 %m2, 31
  %x3 = xor i64 %m2, %r3
  %res = lshr i64 %x3, 1
  ret i64 %res
}

; ------------------------------------------------------------------- input

define internal i64 @read_stdin() {
entry:
  %bufp = alloca ptr
  %capp = alloca i64
  %lenp = alloca i64
  %b0 = call ptr @host_alloc(i64 65536)
  %isnull0 = icmp eq ptr %b0, null
  br i1 %isnull0, label %oom, label %init
init:
  store ptr %b0, ptr %bufp
  store i64 65536, ptr %capp
  store i64 0, ptr %lenp
  br label %loop
loop:
  %len = load i64, ptr %lenp
  %cap = load i64, ptr %capp
  %full = icmp eq i64 %len, %cap
  br i1 %full, label %grow, label %rd
grow:
  %cap2 = shl i64 %cap, 1
  %bold = load ptr, ptr %bufp
  %bnew = call ptr @host_resize(ptr %bold, i64 %cap2)
  %isnull1 = icmp eq ptr %bnew, null
  br i1 %isnull1, label %oom, label %grown
grown:
  store ptr %bnew, ptr %bufp
  store i64 %cap2, ptr %capp
  br label %rd
rd:
  %len1 = load i64, ptr %lenp
  %cap1 = load i64, ptr %capp
  %b = load ptr, ptr %bufp
  %dst = getelementptr i8, ptr %b, i64 %len1
  %room = sub i64 %cap1, %len1
  %n = call i64 @l0_host_read(i64 0, ptr %dst, i64 %room)
  %eof = icmp sle i64 %n, 0
  br i1 %eof, label %build, label %adv
adv:
  %len2 = add i64 %len1, %n
  store i64 %len2, ptr %lenp
  br label %loop
build:
  %bb = load ptr, ptr %bufp
  %total = load i64, ptr %lenp
  br label %bl
; Built back to front so the list ends up in input order.
bl:
  %i = phi i64 [ %total, %build ], [ %i1, %blbody ]
  %acc = phi i64 [ 0, %build ], [ %acc1, %blbody ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %blbody, label %fin
blbody:
  %i1 = sub i64 %i, 1
  %cp = getelementptr i8, ptr %bb, i64 %i1
  %byte = load i8, ptr %cp
  %bv = zext i8 %byte to i64
  %acc1 = call i64 @l0_new_cons(i64 %bv, i64 %acc, i64 2)
  br label %bl
fin:
  call void @l0_host_free(ptr %bb)
  ret i64 %acc
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
}

; ------------------------------------------------------------------ output

; Each element is reduced modulo 256 by truncation, which is also correct
; for negative values.
define internal void @write_list(i64 %l) {
entry:
  %buf = alloca [65536 x i8]
  br label %loop
loop:
  %cur = phi i64 [ %l, %entry ], [ %next, %put ]
  %n = phi i64 [ 0, %entry ], [ %n2, %put ]
  %end = icmp eq i64 %cur, 0
  br i1 %end, label %done, label %body
body:
  %full = icmp eq i64 %n, 65536
  br i1 %full, label %flush, label %put
flush:
  call void @write_mark(i32 1, ptr %buf, i64 %n)
  br label %put
put:
  %n1 = phi i64 [ %n, %body ], [ 0, %flush ]
  %cell = inttoptr i64 %cur to ptr
  %v = load i64, ptr %cell
  %byte = trunc i64 %v to i8
  %slot = getelementptr i8, ptr %buf, i64 %n1
  store i8 %byte, ptr %slot
  %n2 = add i64 %n1, 1
  %np = getelementptr i64, ptr %cell, i64 1
  %next = load i64, ptr %np
  br label %loop
done:
  %any = icmp ugt i64 %n, 0
  br i1 %any, label %last, label %ret
last:
  call void @write_mark(i32 1, ptr %buf, i64 %n)
  br label %ret
ret:
  ret void
}

; Digits are produced from the unsigned magnitude, so the most negative
; integer needs no special case: negating it wraps to itself, which read as
; unsigned is exactly its magnitude.
define internal void @write_int(i32 %fd, i64 %v) {
entry:
  %buf = alloca [24 x i8]
  %neg = icmp slt i64 %v, 0
  %nv = sub i64 0, %v
  %u = select i1 %neg, i64 %nv, i64 %v
  %nlp = getelementptr i8, ptr %buf, i64 23
  store i8 10, ptr %nlp
  br label %loop
loop:
  %x = phi i64 [ %u, %entry ], [ %q, %loop ]
  %pos = phi i64 [ 23, %entry ], [ %p1, %loop ]
  %p1 = sub i64 %pos, 1
  %q = udiv i64 %x, 10
  %r = urem i64 %x, 10
  %d = add i64 %r, 48
  %dc = trunc i64 %d to i8
  %dp = getelementptr i8, ptr %buf, i64 %p1
  store i8 %dc, ptr %dp
  %more = icmp ne i64 %q, 0
  br i1 %more, label %loop, label %sign
sign:
  br i1 %neg, label %minus, label %emit
minus:
  %p2 = sub i64 %p1, 1
  %mp = getelementptr i8, ptr %buf, i64 %p2
  store i8 45, ptr %mp
  br label %emit
emit:
  %start = phi i64 [ %p1, %sign ], [ %p2, %minus ]
  %sp = getelementptr i8, ptr %buf, i64 %start
  %len = sub i64 24, %start
  call void @write_mark(i32 %fd, ptr %sp, i64 %len)
  ret void
}

; Kinds match @l0_main_ret_kind in spec section 10.2.
define internal void @write_result(i64 %v, i64 %kind) {
entry:
  switch i64 %kind, label %list [
    i64 0, label %int
    i64 1, label %bool
  ]
int:
  call void @write_int(i32 1, i64 %v)
  ret void
bool:
  %t = icmp ne i64 %v, 0
  br i1 %t, label %yes, label %no
yes:
  call void @write_mark(i32 1, ptr @s_true, i64 5)
  ret void
no:
  call void @write_mark(i32 1, ptr @s_false, i64 6)
  ret void
list:
  call void @write_list(i64 %v)
  ret void
}

; ------------------------------------------------------------------- stack

; Called on entry to every compiled function. The limit leaves 256 KB of
; headroom, which is what reporting the error, and anything else the runtime
; does from deep in a program's recursion, may use.
define void @l0_stack_check() noinline {
entry:
  %fp = call ptr @llvm.frameaddress.p0(i32 0)
  %f = ptrtoint ptr %fp to i64
  %lim = load i64, ptr @stack_limit
  %low = icmp ult i64 %f, %lim
  br i1 %low, label %err, label %ok
err:
  call void @rt_error(ptr @m_stack, i64 15)
  unreachable
ok:
  ret void
}

; Called by the host file's entry point, with the size of the stack below the
; calling frame, and returns the exit status. Spec section 10.3. Stacks grow
; down on every platform L0 runs on, so the limit is that size below the
; frame where the program starts. L0_RC_CHECK is read here, before anything
; is allocated.
;
; Kind 3 is a main that streams: nothing is read for it, and its result is
; the exit status. The other kinds take the whole input, so standard input is
; marked as already ended. Spec section 9. Either way every handle is flushed
; at the end, as if closed, and then a write failure the program was never
; told of is a runtime error. Spec section 6.3.
define i64 @l0_rt_run(i64 %sz) noinline {
entry:
  %fp = call ptr @llvm.frameaddress.p0(i32 0)
  %f = ptrtoint ptr %fp to i64
  %base = sub i64 %f, %sz
  %lim = add i64 %base, 262144
  store i64 %lim, ptr @stack_limit
  %chkenv = call ptr @l0_host_setting(ptr @check_name)
  %checking = icmp ne ptr %chkenv, null
  %chkv = zext i1 %checking to i64
  store i64 %chkv, ptr @rc_check
  call void @std_handles()
  %k = load i64, ptr @l0_main_ret_kind
  %streams = icmp eq i64 %k, 3
  br i1 %streams, label %stream, label %whole
stream:
  %s = call i64 @l0_f_main(i64 0)
  call void @flush_every()
  %st = and i64 %s, 255
  call void @release_lists()
  call void @check_live()
  call void @report_lost()
  ret i64 %st
whole:
  %in = call i64 @read_stdin()
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 0
  store i64 1, ptr %sp
  %r = call i64 @l0_f_main(i64 %in)
  call void @flush_every()
  call void @write_result(i64 %r, i64 %k)
  %islist = icmp eq i64 %k, 2
  br i1 %islist, label %release, label %checked
release:
  call void @l0_dec(i64 %r)
  br label %checked
checked:
  call void @release_lists()
  call void @check_live()
  call void @report_lost()
  ret i64 0
}
