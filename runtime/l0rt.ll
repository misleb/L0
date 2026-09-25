; l0rt.ll -- the runtime linked into every compiled L0 program. Spec section
; 10.3 is its interface; section 9 is the host half of the contract it
; implements, for either form of main; section 6.2 is what read_byte and
; write_byte promise.
;
; It carries no target triple, and must stay the same text on every host, so
; it avoids everything whose shape differs between operating systems: it
; calls libc through file descriptors rather than FILE*, uses no varargs, no
; signal handling, and no struct whose layout libc defines. pthread_attr_t is
; an opaque buffer larger than any platform's. The only struct it reads is
; struct rlimit, two 64-bit words everywhere, with RLIMIT_STACK = 3 on both
; macOS and Linux.

declare i64 @read(i32, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare void @_exit(i32) noreturn
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @getenv(ptr)
declare i64 @strtol(ptr, ptr, i32)
declare i32 @getrlimit(i32, ptr)
declare i32 @pthread_attr_init(ptr)
declare i32 @pthread_attr_setstacksize(ptr, i64)
declare i32 @pthread_create(ptr, ptr, ptr, ptr)
declare i32 @pthread_join(i64, ptr)
declare i32 @open(ptr, i32, ...)
declare i32 @creat(ptr, i32)
declare i32 @close(i32)
declare i32 @access(ptr, i32)
declare ptr @llvm.frameaddress.p0(i32)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)

; Defined by the generated IR. Spec section 10.2.
declare i64 @l0_f_main(i64)
@l0_main_ret_kind = external global i64

@arena_cur = internal global i64 0
@arena_end = internal global i64 0
@stack_limit = internal global i64 0
@stack_bytes = internal global i64 0
@exit_status = internal global i64 0

@argc = internal global i64 0
@argv = internal global ptr null

; The handle table of spec section 6.3. A handle is an index into it. mode is
; 0 for closed, 1 for reading, and 2 for writing; state is 0 when all is well,
; 1 once end of input is seen, 2 after a read failed, 3 after a write failed
; that no flush or close has reported, and 4 once one has. Every state but 0
; sticks, so a terminal is not asked for a second end of file, and a lost
; byte is never forgotten; a new write failure turns 4 back into 3.
; For reading, pos and len delimit the unread bytes in buf; for writing, len
; is how many bytes are held back. Handles 0, 1, and 2 use the static buffers
; below and are never closed; the rest get a buffer from malloc when opened.
@h_fd = internal global [64 x i64] zeroinitializer
@h_mode = internal global [64 x i64] zeroinitializer
@h_state = internal global [64 x i64] zeroinitializer
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
@env_name = private constant [12 x i8] c"L0_STACK_MB\00"
@check_name = private constant [12 x i8] c"L0_RC_CHECK\00"
@m_uaf = private constant [20 x i8] c"use of a freed block"
@m_live = private constant [23 x i8] c"l0: blocks still live: "

; ------------------------------------------------------------------ errors

; Returns 0 if every byte was written, -1 if the descriptor refused some.
define internal i64 @write_all_rc(i32 %fd, ptr %p, i64 %n) {
entry:
  br label %loop
loop:
  %cp = phi ptr [ %p, %entry ], [ %np, %more ]
  %cn = phi i64 [ %n, %entry ], [ %nn, %more ]
  %done = icmp sle i64 %cn, 0
  br i1 %done, label %ok, label %body
body:
  %w = call i64 @write(i32 %fd, ptr %cp, i64 %cn)
  %bad = icmp sle i64 %w, 0
  br i1 %bad, label %fail, label %more
more:
  %np = getelementptr i8, ptr %cp, i64 %w
  %nn = sub i64 %cn, %w
  br label %loop
ok:
  ret i64 0
fail:
  ret i64 -1
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
; as spec section 8 requires. _exit skips atexit handlers.
define internal void @rt_error(ptr %m, i64 %n) noreturn noinline {
entry:
  call void @flush_every()
  call void @write_all(i32 2, ptr @pfx, i64 19)
  call void @write_all(i32 2, ptr %m, i64 %n)
  call void @write_all(i32 2, ptr @nl, i64 1)
  call void @_exit(i32 70)
  unreachable
}

; ------------------------------------------------------------------- arena

; Chunks come from malloc, and every allocation is a whole number of words.
define internal i64 @arena_alloc(i64 %bytes) {
entry:
  %b1 = add i64 %bytes, 7
  %b = and i64 %b1, -8
  %cur = load i64, ptr @arena_cur
  %end = load i64, ptr @arena_end
  %room = sub i64 %end, %cur
  %fits = icmp uge i64 %room, %b
  br i1 %fits, label %take, label %grow
grow:
  %big = icmp ugt i64 %b, 67108864
  %want = select i1 %big, i64 %b, i64 67108864
  %chunk = call ptr @malloc(i64 %want)
  %null = icmp eq ptr %chunk, null
  br i1 %null, label %oom, label %ok
oom:
  call void @rt_error(ptr @m_heap, i64 14)
  unreachable
ok:
  %c = ptrtoint ptr %chunk to i64
  %e = add i64 %c, %want
  store i64 %e, ptr @arena_end
  br label %take
take:
  %p = phi i64 [ %cur, %entry ], [ %c, %ok ]
  %np = add i64 %p, %b
  store i64 %np, ptr @arena_cur
  ret i64 %p
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
; built stay correct. A freed block goes on the free list for its size,
; threaded through its header word, and allocation takes from there before
; the arena.

@free_lists = internal global [257 x i64] zeroinitializer

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
  %small = icmp ule i64 %total, 256
  br i1 %small, label %try, label %fresh
try:
  %fp = getelementptr [257 x i64], ptr @free_lists, i64 0, i64 %total
  %top = load i64, ptr %fp
  %have = icmp ne i64 %top, 0
  br i1 %have, label %reuse, label %fresh
reuse:
  %tq = inttoptr i64 %top to ptr
  %next = load i64, ptr %tq
  store i64 %next, ptr %fp
  br label %init
fresh:
  %bytes = mul i64 %total, 8
  %new = call i64 @arena_alloc(i64 %bytes)
  br label %init
init:
  %blk = phi i64 [ %top, %reuse ], [ %new, %fresh ]
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
  %new = call ptr @realloc(ptr %old, i64 %bytes)
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
  br label %scan
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
  %small = icmp ule i64 %total, 256
  br i1 %small, label %onlist, label %out
onlist:
  %fp = getelementptr [257 x i64], ptr @free_lists, i64 0, i64 %total
  %top = load i64, ptr %fp
  store i64 %top, ptr %hq
  store i64 %hp, ptr %fp
  br label %out
out:
  ret void
}

; Under L0_RC_CHECK, reports counted blocks still live at a normal exit.
define internal void @check_live() {
entry:
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
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  store i64 %fd, ptr %fp
  %mp = getelementptr [64 x i64], ptr @h_mode, i64 0, i64 %h
  store i64 %mode, ptr %mp
  %sp = getelementptr [64 x i64], ptr @h_state, i64 0, i64 %h
  store i64 0, ptr %sp
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
  br label %done
done:
  %st = load i64, ptr %sp
  %err = icmp uge i64 %st, 3
  %r = select i1 %err, i64 -5, i64 0
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
  br i1 %err, label %failed, label %chk
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
  %fd32 = trunc i64 %fd to i32
  %n = call i64 @read(i32 %fd32, ptr %buf, i64 65536)
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
  %full = icmp eq i64 %n, 65536
  br i1 %full, label %flush, label %put
flush:
  %r = call i64 @h_flush(i64 %h)
  br label %put
put:
  %n1 = phi i64 [ %n, %go ], [ 0, %flush ]
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
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
  %fp = getelementptr [64 x i64], ptr @h_fd, i64 0, i64 %h
  %fd = load i64, ptr %fp
  %fd32 = trunc i64 %fd to i32
  %c = call i32 @close(i32 %fd32)
  %bp = getelementptr [64 x ptr], ptr @h_buf, i64 0, i64 %h
  %buf = load ptr, ptr %bp
  call void @free(ptr %buf)
  %mp = getelementptr [64 x i64], ptr @h_mode, i64 0, i64 %h
  store i64 0, ptr %mp
  %cfail = icmp ne i32 %c, 0
  %final = select i1 %cfail, i64 -5, i64 %res
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
  %s = call ptr @malloc(i64 %sz)
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
  call void @free(ptr %s)
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

; mode 1 opens for reading and mode 2 creates or empties for writing. The
; results are spec section 6.3's. Reading only opens with flags 0 and writing
; uses creat, because O_CREAT and O_TRUNC differ between macOS and Linux; and
; errno is not reachable portably, so access() tells why an open failed.
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
  %b = call ptr @malloc(i64 65536)
  %nob = icmp eq ptr %b, null
  br i1 %nob, label %other_free, label %which
which:
  br i1 %rd, label %openr, label %openw
openr:
  %fr = call i32 (ptr, i32, ...) @open(ptr %s, i32 0)
  br label %opened
openw:
  %fw = call i32 @creat(ptr %s, i32 420)
  br label %opened
opened:
  %fd = phi i32 [ %fr, %openr ], [ %fw, %openw ]
  %failed = icmp slt i32 %fd, 0
  br i1 %failed, label %why, label %ok
ok:
  %fd64 = sext i32 %fd to i64
  call void @h_set(i64 %h, i64 %fd64, i64 %mode, ptr %b)
  call void @free(ptr %s)
  ret i64 %h
why:
  call void @free(ptr %b)
  %exists = call i32 @access(ptr %s, i32 0)
  %missing = icmp ne i32 %exists, 0
  %want = select i1 %rd, i32 4, i32 2
  %may = call i32 @access(ptr %s, i32 %want)
  %denied = icmp ne i32 %may, 0
  call void @free(ptr %s)
  br i1 %missing, label %gone, label %present
gone:
  %g = select i1 %rd, i64 -3, i64 -5
  ret i64 %g
present:
  %p = select i1 %denied, i64 -4, i64 -5
  ret i64 %p
other_free:
  call void @free(ptr %s)
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

; --------------------------------------------------------------- arguments

define i64 @l0_arg_count() {
entry:
  %c = load i64, ptr @argc
  %n = sub i64 %c, 1
  %neg = icmp slt i64 %n, 0
  %r = select i1 %neg, i64 0, i64 %n
  ret i64 %r
}

; argv[0] is the program's own name, so argument i is argv[i + 1].
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
  %av = load ptr, ptr @argv
  %i1 = add i64 %i, 1
  %ap = getelementptr ptr, ptr %av, i64 %i1
  %s = load ptr, ptr %ap
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

; ------------------------------------------------------------------- input

define internal i64 @read_stdin() {
entry:
  %bufp = alloca ptr
  %capp = alloca i64
  %lenp = alloca i64
  %b0 = call ptr @malloc(i64 65536)
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
  %bnew = call ptr @realloc(ptr %bold, i64 %cap2)
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
  %n = call i64 @read(i32 0, ptr %dst, i64 %room)
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
  call void @free(ptr %bb)
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

; Stacks grow down on every platform L0 runs on, so the limit is the stack's
; size below the frame where the program starts.
;
; Kind 3 is a main that streams: nothing is read for it, and its result is
; the exit status. The other kinds take the whole input, so standard input is
; marked as already ended. Spec section 9. Either way every handle is flushed
; at the end, as if closed, and then a write failure the program was never
; told of is a runtime error. Spec section 6.3.
define internal ptr @run(ptr %unused) noinline {
entry:
  %fp = call ptr @llvm.frameaddress.p0(i32 0)
  %f = ptrtoint ptr %fp to i64
  %sz = load i64, ptr @stack_bytes
  %base = sub i64 %f, %sz
  %lim = add i64 %base, 262144
  store i64 %lim, ptr @stack_limit
  call void @std_handles()
  %k = load i64, ptr @l0_main_ret_kind
  %streams = icmp eq i64 %k, 3
  br i1 %streams, label %stream, label %whole
stream:
  %s = call i64 @l0_f_main(i64 0)
  call void @flush_every()
  %st = and i64 %s, 255
  store i64 %st, ptr @exit_status
  call void @check_live()
  call void @report_lost()
  ret ptr null
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
  call void @check_live()
  call void @report_lost()
  ret ptr null
}

; The size of the calling thread's stack, for when a thread of the requested
; size could not be created. RLIM_INFINITY differs between platforms, so any
; limit too large to be real is treated as the common 8 MB default.
define internal i64 @own_stack_bytes() {
entry:
  %rl = alloca [2 x i64], align 8
  %rc = call i32 @getrlimit(i32 3, ptr %rl)
  %failed = icmp ne i32 %rc, 0
  %cur = load i64, ptr %rl
  %huge = icmp ugt i64 %cur, 4398046511104
  %small = icmp ult i64 %cur, 1048576
  %bad1 = or i1 %failed, %huge
  %bad = or i1 %bad1, %small
  %r = select i1 %bad, i64 8388608, i64 %cur
  ret i64 %r
}

; The stack size comes from L0_STACK_MB, default 512.
define i32 @main(i32 %argc, ptr %argv) {
entry:
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @argc
  store ptr %argv, ptr @argv
  %attr = alloca [128 x i8], align 16
  %tid = alloca i64
  %chkenv = call ptr @getenv(ptr @check_name)
  %checking = icmp ne ptr %chkenv, null
  %chkv = zext i1 %checking to i64
  store i64 %chkv, ptr @rc_check
  %env = call ptr @getenv(ptr @env_name)
  %hasenv = icmp ne ptr %env, null
  br i1 %hasenv, label %parse, label %go
parse:
  %v = call i64 @strtol(ptr %env, ptr null, i32 10)
  %pos = icmp sgt i64 %v, 0
  %mb = select i1 %pos, i64 %v, i64 512
  br label %go
go:
  %m = phi i64 [ %mb, %parse ], [ 512, %entry ]
  %bytes = mul i64 %m, 1048576
  store i64 %bytes, ptr @stack_bytes
  %a = call i32 @pthread_attr_init(ptr %attr)
  %s = call i32 @pthread_attr_setstacksize(ptr %attr, i64 %bytes)
  %c = call i32 @pthread_create(ptr %tid, ptr %attr, ptr @run, ptr null)
  %failed = icmp ne i32 %c, 0
  br i1 %failed, label %direct, label %join
join:
  %t = load i64, ptr %tid
  %j = call i32 @pthread_join(i64 %t, ptr null)
  br label %exit
direct:
  %own = call i64 @own_stack_bytes()
  store i64 %own, ptr @stack_bytes
  %x = call ptr @run(ptr null)
  br label %exit
exit:
  %st = load i64, ptr @exit_status
  %st32 = trunc i64 %st to i32
  ret i32 %st32
}
