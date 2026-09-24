; l0rt.ll -- the runtime linked into every compiled L0 program. Spec section
; 10.3 is its interface; section 9 is the host half of the contract it
; implements: read stdin into a byte list, apply main, write the result.
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
declare ptr @llvm.frameaddress.p0(i32)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)

; Defined by the generated IR. Spec section 10.2.
declare i64 @l0_f_main(i64)
@l0_main_ret_kind = external global i64

@arena_cur = internal global i64 0
@arena_end = internal global i64 0
@stack_limit = internal global i64 0
@stack_bytes = internal global i64 0

@pfx = private constant [19 x i8] c"l0: runtime error: "
@nl = private constant [1 x i8] c"\0A"
@m_heap = private constant [14 x i8] c"heap exhausted"
@m_head = private constant [18 x i8] c"head of empty list"
@m_tail = private constant [18 x i8] c"tail of empty list"
@m_div = private constant [16 x i8] c"division by zero"
@m_mod = private constant [14 x i8] c"modulo by zero"
@m_stack = private constant [15 x i8] c"stack exhausted"
@s_true = private constant [5 x i8] c"true\0A"
@s_false = private constant [6 x i8] c"false\0A"
@env_name = private constant [12 x i8] c"L0_STACK_MB\00"

; ------------------------------------------------------------------ errors

define internal void @write_all(i32 %fd, ptr %p, i64 %n) {
entry:
  br label %loop
loop:
  %cp = phi ptr [ %p, %entry ], [ %np, %more ]
  %cn = phi i64 [ %n, %entry ], [ %nn, %more ]
  %done = icmp sle i64 %cn, 0
  br i1 %done, label %out, label %body
body:
  %w = call i64 @write(i32 %fd, ptr %cp, i64 %cn)
  %bad = icmp sle i64 %w, 0
  br i1 %bad, label %out, label %more
more:
  %np = getelementptr i8, ptr %cp, i64 %w
  %nn = sub i64 %cn, %w
  br label %loop
out:
  ret void
}

; Standard output is written only after main returns, so a runtime error
; leaves it empty, as spec section 8 requires. _exit skips atexit handlers.
define internal void @rt_error(ptr %m, i64 %n) noreturn noinline {
entry:
  call void @write_all(i32 2, ptr @pfx, i64 19)
  call void @write_all(i32 2, ptr %m, i64 %n)
  call void @write_all(i32 2, ptr @nl, i64 1)
  call void @_exit(i32 70)
  unreachable
}

; ------------------------------------------------------------------- arena

; Never frees, which spec section 10.3 explains. Chunks come from malloc,
; which aligns to 16 bytes, and every allocation is rounded up to 16.
define internal i64 @arena_alloc(i64 %bytes) {
entry:
  %b1 = add i64 %bytes, 15
  %b = and i64 %b1, -16
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

; ------------------------------------------------------- lists and blocks

define i64 @l0_cons(i64 %h, i64 %t) {
entry:
  %p = call i64 @arena_alloc(i64 16)
  %q = inttoptr i64 %p to ptr
  store i64 %h, ptr %q
  %q1 = getelementptr i64, ptr %q, i64 1
  store i64 %t, ptr %q1
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
  %n1 = add i64 %n, 1
  %bytes = mul i64 %n1, 8
  %p = call i64 @arena_alloc(i64 %bytes)
  %q = inttoptr i64 %p to ptr
  call void @llvm.memset.p0.i64(ptr %q, i8 0, i64 %bytes, i1 false)
  store i64 %tag, ptr %q
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
  %acc1 = call i64 @l0_cons(i64 %bv, i64 %acc)
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
  call void @write_all(i32 1, ptr %buf, i64 %n)
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
  call void @write_all(i32 1, ptr %buf, i64 %n)
  br label %ret
ret:
  ret void
}

; Digits are produced from the unsigned magnitude, so the most negative
; integer needs no special case: negating it wraps to itself, which read as
; unsigned is exactly its magnitude.
define internal void @write_int(i64 %v) {
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
  call void @write_all(i32 1, ptr %sp, i64 %len)
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
  call void @write_int(i64 %v)
  ret void
bool:
  %t = icmp ne i64 %v, 0
  br i1 %t, label %yes, label %no
yes:
  call void @write_all(i32 1, ptr @s_true, i64 5)
  ret void
no:
  call void @write_all(i32 1, ptr @s_false, i64 6)
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
define internal ptr @run(ptr %unused) noinline {
entry:
  %fp = call ptr @llvm.frameaddress.p0(i32 0)
  %f = ptrtoint ptr %fp to i64
  %sz = load i64, ptr @stack_bytes
  %base = sub i64 %f, %sz
  %lim = add i64 %base, 262144
  store i64 %lim, ptr @stack_limit
  %in = call i64 @read_stdin()
  %r = call i64 @l0_f_main(i64 %in)
  %k = load i64, ptr @l0_main_ret_kind
  call void @write_result(i64 %r, i64 %k)
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
define i32 @main() {
entry:
  %attr = alloca [128 x i8], align 16
  %tid = alloca i64
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
  ret i32 0
direct:
  %own = call i64 @own_stack_bytes()
  store i64 %own, ptr @stack_bytes
  %x = call ptr @run(ptr null)
  ret i32 0
}
