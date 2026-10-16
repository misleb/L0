; host-libc.ll -- the host file for an operating system reached through
; libc, macOS and Linux. It is the only part of the runtime that calls libc:
; runtime/l0rt.ll calls the l0_host_ functions below and nothing else of the
; host's, and this file defines the process entry point, which calls
; @l0_rt_run. Spec section 10.3 is the interface between the two.
;
; It carries no target triple, and must stay the same text on every host, so
; it avoids everything whose shape differs between operating systems: it
; calls libc through file descriptors rather than FILE*, but for the one
; fopen that opens for appending; passes no variadic argument, since open,
; declared variadic as libc's is, is only ever given its two fixed ones; and
; uses no signal handling beyond ignoring SIGPIPE, which is 13 with SIG_IGN 1
; on both macOS and Linux, and no struct whose layout libc defines. errno is
; reached through whichever of macOS's __error and Linux's __errno_location
; dlsym finds, and only codes with the same number on both are read from it
; (host_setup). pthread_attr_t is an opaque buffer larger than any
; platform's, and a FILE or DIR pointer is only handed back to libc, never
; read. The only structs it reads are struct rlimit, two 64-bit words
; everywhere, with RLIMIT_STACK = 3 on both macOS and Linux, and struct
; timespec, two 64-bit words everywhere, with CLOCK_MONOTONIC_RAW = 4 on
; both.
;
; A stream is a file descriptor, and standard input, output, and error are
; descriptors 0, 1, and 2, as spec section 10.3 numbers them.

declare i64 @read(i32, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare void @_exit(i32) noreturn
declare ptr @malloc(i64)
declare i32 @posix_memalign(ptr, i64, i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @getenv(ptr)
declare i64 @strtol(ptr, ptr, i32)
declare i32 @getrlimit(i32, ptr)
declare i32 @clock_gettime(i32, ptr)
declare i32 @pthread_attr_init(ptr)
declare i32 @pthread_attr_setstacksize(ptr, i64)
declare i32 @pthread_create(ptr, ptr, ptr, ptr)
declare i32 @pthread_join(i64, ptr)
declare i32 @open(ptr, i32, ...)
declare i32 @creat(ptr, i32)
declare i32 @close(i32)
declare i32 @access(ptr, i32)
declare i32 @rename(ptr, ptr)
declare i32 @unlink(ptr)
declare i32 @dup(i32)
declare ptr @fopen(ptr, ptr)
declare i32 @fileno(ptr)
declare i32 @fclose(ptr)
declare ptr @opendir(ptr)
declare i32 @closedir(ptr)
declare ptr @signal(i32, ptr)
declare ptr @dlopen(ptr, i32)
declare ptr @dlsym(ptr, ptr)

; Defined by runtime/l0rt.ll. Spec section 10.3.
declare i64 @l0_rt_run(i64)

@argc = internal global i64 0
@argv = internal global ptr null
@stack_bytes = internal global i64 0
@exit_status = internal global i64 0

@env_name = private constant [12 x i8] c"L0_STACK_MB\00"
@mode_a = private constant [2 x i8] c"a\00"
@dev_null = private constant [10 x i8] c"/dev/null\00"
@s_error = private constant [8 x i8] c"__error\00"
@s_errno_loc = private constant [17 x i8] c"__errno_location\00"

; The host's function returning a pointer to the calling thread's errno, or
; null if neither name was found, in which case causes are not told apart.
@errno_fn = internal global ptr null

; ------------------------------------------------------------------ memory

define ptr @l0_host_alloc(i64 %n) {
entry:
  %p = call ptr @malloc(i64 %n)
  ret ptr %p
}

define ptr @l0_host_alloc_aligned(i64 %align, i64 %n) {
entry:
  %slot = alloca ptr
  %r = call i32 @posix_memalign(ptr %slot, i64 %align, i64 %n)
  %ok = icmp eq i32 %r, 0
  br i1 %ok, label %got, label %none
got:
  %p = load ptr, ptr %slot
  ret ptr %p
none:
  ret ptr null
}

define ptr @l0_host_resize(ptr %p, i64 %n) {
entry:
  %q = call ptr @realloc(ptr %p, i64 %n)
  ret ptr %q
}

define void @l0_host_free(ptr %p) {
entry:
  call void @free(ptr %p)
  ret void
}

; ------------------------------------------------------------------- errno

; errno, as the libc call just made left it, or -1 if it cannot be read.
; Called before anything else that may set it.
define internal i32 @last_errno() {
entry:
  %f = load ptr, ptr @errno_fn
  %none = icmp eq ptr %f, null
  br i1 %none, label %unknown, label %read
read:
  %p = call ptr %f()
  %e = load i32, ptr %p
  ret i32 %e
unknown:
  ret i32 -1
}

; Whether a name access could not find is missing, by its errno: ENOENT (2)
; or ENOTDIR (20), the same on macOS and Linux. A loop of links or a name
; too long is not. When errno cannot be read, every such name is taken to
; be missing, as it was before errno could be.
define internal i1 @errno_missing(i32 %e) {
entry:
  %unknown = icmp eq i32 %e, -1
  %noent = icmp eq i32 %e, 2
  %notdir = icmp eq i32 %e, 20
  %a = or i1 %unknown, %noent
  %b = or i1 %a, %notdir
  ret i1 %b
}

; Whether errno e says permission was refused: EACCES (13), EPERM (1), or
; EROFS (30), a read-only file system, the same numbers on macOS and Linux.
define internal i1 @errno_refused(i32 %e) {
entry:
  %acces = icmp eq i32 %e, 13
  %perm = icmp eq i32 %e, 1
  %rofs = icmp eq i32 %e, 30
  %a = or i1 %acces, %perm
  %b = or i1 %a, %rofs
  ret i1 %b
}

; The spec section 6.3 code for a write or close that just failed, by errno:
; ENOSPC (28) is -6 and EPIPE (32) -7, the same numbers on macOS and Linux,
; and anything else, or no errno, -5.
define internal i64 @write_code() {
entry:
  %e = call i32 @last_errno()
  %full = icmp eq i32 %e, 28
  %pipe = icmp eq i32 %e, 32
  %a = select i1 %pipe, i64 -7, i64 -5
  %b = select i1 %full, i64 -6, i64 %a
  ret i64 %b
}

; ----------------------------------------------------------------- streams

define i64 @l0_host_read(i64 %s, ptr %buf, i64 %n) {
entry:
  %fd = trunc i64 %s to i32
  %r = call i64 @read(i32 %fd, ptr %buf, i64 %n)
  %bad = icmp slt i64 %r, 0
  %res = select i1 %bad, i64 -5, i64 %r
  ret i64 %res
}

; A write that writes nothing has failed, as one that returns -1 has.
define i64 @l0_host_write(i64 %s, ptr %buf, i64 %n) {
entry:
  %fd = trunc i64 %s to i32
  %w = call i64 @write(i32 %fd, ptr %buf, i64 %n)
  %ok = icmp sgt i64 %w, 0
  br i1 %ok, label %wrote, label %failed
wrote:
  ret i64 %w
failed:
  %why = call i64 @write_code()
  ret i64 %why
}

define i64 @l0_host_close(i64 %s) {
entry:
  %fd = trunc i64 %s to i32
  %c = call i32 @close(i32 %fd)
  %ok = icmp eq i32 %c, 0
  br i1 %ok, label %closed, label %failed
closed:
  ret i64 0
failed:
  %why = call i64 @write_code()
  ret i64 %why
}

; ------------------------------------------------------------------- files

; A descriptor open for writing at the end of the file s, or -1. O_APPEND and
; O_CREAT differ between macOS and Linux, so append mode comes from fopen,
; whose descriptor is duplicated before the FILE is closed. A missing file
; is created first with creat, so that it gets the permissions open_write
; would give it.
define internal i32 @open_end(ptr %s) {
entry:
  %ex = call i32 @access(ptr %s, i32 0)
  %missing = icmp ne i32 %ex, 0
  br i1 %missing, label %create, label %append
create:
  %c = call i32 @creat(ptr %s, i32 420)
  %cfail = icmp slt i32 %c, 0
  br i1 %cfail, label %fail, label %created
created:
  %cc = call i32 @close(i32 %c)
  br label %append
append:
  %fp = call ptr @fopen(ptr %s, ptr @mode_a)
  %nofp = icmp eq ptr %fp, null
  br i1 %nofp, label %fail, label %dup
dup:
  %fd = call i32 @fileno(ptr %fp)
  %d = call i32 @dup(i32 %fd)
  %fc = call i32 @fclose(ptr %fp)
  ret i32 %d
fail:
  ret i32 -1
}

; mode 1 opens for reading, 2 creates or empties for writing, and 3 opens
; for writing at the end. The results are spec section 6.3's. Reading only
; opens with flags 0 and writing uses creat, because O_CREAT and O_TRUNC
; differ between macOS and Linux. The open's errno tells why it failed
; (open_code); without errno, access() tells a missing name from a denied
; one, and everything else is -5. A directory opens with flags 0 but cannot
; be read, so opendir tells it apart first.
define i64 @l0_host_open(ptr %s, i64 %mode) {
entry:
  %rd = icmp eq i64 %mode, 1
  br i1 %rd, label %isdir, label %writing
isdir:
  %dp = call ptr @opendir(ptr %s)
  %dir = icmp ne ptr %dp, null
  br i1 %dir, label %directory, label %openr
directory:
  %cd = call i32 @closedir(ptr %dp)
  ret i64 -8
writing:
  %ap = icmp eq i64 %mode, 3
  br i1 %ap, label %opena, label %openw
openr:
  %fr = call i32 (ptr, i32, ...) @open(ptr %s, i32 0)
  br label %opened
openw:
  %fw = call i32 @creat(ptr %s, i32 420)
  br label %opened
opena:
  %fa = call i32 @open_end(ptr %s)
  br label %opened
opened:
  %fd = phi i32 [ %fr, %openr ], [ %fw, %openw ], [ %fa, %opena ]
  %failed = icmp slt i32 %fd, 0
  br i1 %failed, label %why, label %ok
ok:
  %fd64 = sext i32 %fd to i64
  ret i64 %fd64
why:
  %oe = call i32 @last_errno()
  %known = icmp ne i32 %oe, -1
  br i1 %known, label %by_errno, label %guess
by_errno:
  %code = call i64 @open_code(i32 %oe, i1 %rd)
  ret i64 %code
guess:
  %exists = call i32 @access(ptr %s, i32 0)
  %unfound = icmp ne i32 %exists, 0
  %want = select i1 %rd, i32 4, i32 2
  %may = call i32 @access(ptr %s, i32 %want)
  %denied = icmp ne i32 %may, 0
  br i1 %unfound, label %gone, label %present
gone:
  %g = select i1 %rd, i64 -3, i64 -5
  ret i64 %g
present:
  %p = select i1 %denied, i64 -4, i64 -5
  ret i64 %p
}

; The spec section 6.3 code of an open that failed with errno e. Reading: a
; missing name is -3, refused -4, a directory (EISDIR, 21) -8. Writing: a
; directory -8; a missing name means the directory it would be in is
; missing, -9; refused -4. Anything else is -5.
define internal i64 @open_code(i32 %e, i1 %rd) {
entry:
  %missing = call i1 @errno_missing(i32 %e)
  %refused = call i1 @errno_refused(i32 %e)
  %isdir = icmp eq i32 %e, 21
  %r1 = select i1 %isdir, i64 -8, i64 -5
  %r2 = select i1 %refused, i64 -4, i64 %r1
  %r3 = select i1 %missing, i64 -3, i64 %r2
  %w1 = select i1 %refused, i64 -4, i64 -5
  %w2 = select i1 %missing, i64 -9, i64 %w1
  %w3 = select i1 %isdir, i64 -8, i64 %w2
  %r = select i1 %rd, i64 %r3, i64 %w3
  ret i64 %r
}

; POSIX rename replaces to in one step, as spec section 6.3 requires. When
; it fails, its errno says why: EXDEV (18) is -10, refused -4, a missing name
; -3 if from is missing, -9 if to is too, since then to's directory is, and
; otherwise -5, since a directory renamed onto a file gives ENOTDIR with
; both names there; and to being a directory, by EISDIR (21) or by opendir,
; since a full one gives ENOTEMPTY, numbered differently on macOS and Linux,
; is -8. Without errno, only a missing from is told apart, by access.
define i64 @l0_host_rename(ptr %a, ptr %b) {
entry:
  %r = call i32 @rename(ptr %a, ptr %b)
  %ok = icmp eq i32 %r, 0
  br i1 %ok, label %done, label %why
done:
  ret i64 0
why:
  %re = call i32 @last_errno()
  %ex = call i32 @access(ptr %a, i32 0)
  %ae = call i32 @last_errno()
  %tx = call i32 @access(ptr %b, i32 0)
  %dp = call ptr @opendir(ptr %b)
  %todir = icmp ne ptr %dp, null
  br i1 %todir, label %shut, label %decide
shut:
  %cd = call i32 @closedir(ptr %dp)
  br label %decide
decide:
  %unfound = icmp ne i32 %ex, 0
  %srcgone = call i1 @errno_missing(i32 %ae)
  %fromgone = and i1 %unfound, %srcgone
  %known = icmp ne i32 %re, -1
  br i1 %known, label %by_errno, label %guess
guess:
  %g = select i1 %fromgone, i64 -3, i64 -5
  ret i64 %g
by_errno:
  %xdev = icmp eq i32 %re, 18
  %refused = call i1 @errno_refused(i32 %re)
  %missing = call i1 @errno_missing(i32 %re)
  %eisdir = icmp eq i32 %re, 21
  %isdir = or i1 %eisdir, %todir
  %toseen = icmp eq i32 %tx, 0
  %tocode = select i1 %toseen, i64 -5, i64 -9
  %nodir = select i1 %fromgone, i64 -3, i64 %tocode
  %c1 = select i1 %isdir, i64 -8, i64 -5
  %c2 = select i1 %missing, i64 %nodir, i64 %c1
  %c3 = select i1 %refused, i64 -4, i64 %c2
  %c4 = select i1 %xdev, i64 -10, i64 %c3
  ret i64 %c4
}

; unlink deletes a name in one step, and a link rather than what it leads
; to, as spec section 6.3 requires. When it fails, a directory (-8) is told
; apart first, since macOS refuses one with EPERM, which otherwise means
; denied; then errno says missing (-3) or denied (-4). Without errno, a name
; access cannot find is missing, and every other failure -5.
define i64 @l0_host_remove(ptr %s) {
entry:
  %r = call i32 @unlink(ptr %s)
  %ok = icmp eq i32 %r, 0
  br i1 %ok, label %done, label %why
done:
  ret i64 0
why:
  %e = call i32 @last_errno()
  %dp = call ptr @opendir(ptr %s)
  %dir = icmp ne ptr %dp, null
  br i1 %dir, label %directory, label %file
directory:
  %cd = call i32 @closedir(ptr %dp)
  ret i64 -8
file:
  %ex = call i32 @access(ptr %s, i32 0)
  %unknown = icmp eq i32 %e, -1
  br i1 %unknown, label %guess, label %known
guess:
  %unfound = icmp ne i32 %ex, 0
  %g = select i1 %unfound, i64 -3, i64 -5
  ret i64 %g
known:
  %nothing = call i1 @errno_missing(i32 %e)
  %refused = call i1 @errno_refused(i32 %e)
  %rr = select i1 %refused, i64 -4, i64 -5
  %rk = select i1 %nothing, i64 -3, i64 %rr
  ret i64 %rk
}

; ------------------------------------------- the clock, arguments, settings

; Clock 4 is CLOCK_MONOTONIC_RAW on both macOS and Linux; CLOCK_MONOTONIC is
; not, and Linux's 6 is a coarse clock, not an error.
define i64 @l0_host_clock_ns() {
entry:
  %ts = alloca [2 x i64], align 8
  %rc = call i32 @clock_gettime(i32 4, ptr %ts)
  %failed = icmp ne i32 %rc, 0
  br i1 %failed, label %none, label %read
none:
  ret i64 -5
read:
  %s = load i64, ptr %ts
  %np = getelementptr i64, ptr %ts, i64 1
  %n = load i64, ptr %np
  %sn = mul i64 %s, 1000000000
  %t = add i64 %sn, %n
  ret i64 %t
}

define i64 @l0_host_arg_count() {
entry:
  %c = load i64, ptr @argc
  %n = sub i64 %c, 1
  %neg = icmp slt i64 %n, 0
  %r = select i1 %neg, i64 0, i64 %n
  ret i64 %r
}

; argv[0] is the program's own name, so argument i is argv[i + 1].
define ptr @l0_host_arg(i64 %i) {
entry:
  %av = load ptr, ptr @argv
  %i1 = add i64 %i, 1
  %ap = getelementptr ptr, ptr %av, i64 %i1
  %s = load ptr, ptr %ap
  ret ptr %s
}

define ptr @l0_host_setting(ptr %name) {
entry:
  %v = call ptr @getenv(ptr %name)
  ret ptr %v
}

; _exit skips atexit handlers.
define void @l0_host_exit(i64 %status) noreturn {
entry:
  %s = trunc i64 %status to i32
  call void @_exit(i32 %s)
  unreachable
}

; Spec section 9.2: an operating system gives a program no device memory,
; so no region, and the barrier has only memory to order.
define i64 @l0_host_region(i64 %base, i64 %len) {
entry:
  ret i64 -3
}

define void @l0_host_barrier() {
entry:
  fence seq_cst
  ret void
}

; Spec section 9.2: no user mode under an operating system, so no space or
; frame is ever made, and anything given one is told 1, not a space, or for
; a frame's address or freeing a frame 2, not a frame.
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

; Spec section 9.2: no interrupts under an operating system, so none is
; ever taken, and ending one is told 8, interrupt not taken.
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

; Spec section 9.2: no kernel beneath a program under an operating system
; answers a call of its own.
define i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %b, i64 %c) {
entry:
  ret i64 -3
}

; ------------------------------------------------------------- entry point

; Before the program's thread starts, spec section 6.3. A write to a pipe
; whose reader has gone fails rather than stopping the process. A standard
; descriptor the host left closed is opened on /dev/null in the other
; direction, so every read or write of it fails and no file the program
; opens takes its number. And errno's accessor is found.
define internal void @host_setup() {
entry:
  %old = call ptr @signal(i32 13, ptr inttoptr (i64 1 to ptr))
  call void @std_fd_fill(i32 0, i32 1)
  call void @std_fd_fill(i32 1, i32 0)
  call void @std_fd_fill(i32 2, i32 0)
  %self = call ptr @dlopen(ptr null, i32 1)
  %none = icmp eq ptr %self, null
  br i1 %none, label %done, label %look
look:
  %e1 = call ptr @dlsym(ptr %self, ptr @s_error)
  %got = icmp ne ptr %e1, null
  br i1 %got, label %keep, label %linux
keep:
  store ptr %e1, ptr @errno_fn
  br label %done
linux:
  %e2 = call ptr @dlsym(ptr %self, ptr @s_errno_loc)
  store ptr %e2, ptr @errno_fn
  br label %done
done:
  ret void
}

; fd, if the host left it closed, opened on /dev/null with flags: 1, write
; only, for standard input, and 0, read only, for the other two. dup fails
; only for a descriptor that is not open, and open takes the lowest free
; number, which is fd once every lower one is open.
define internal void @std_fd_fill(i32 %fd, i32 %flags) {
entry:
  %d = call i32 @dup(i32 %fd)
  %closed = icmp slt i32 %d, 0
  br i1 %closed, label %fill, label %open
open:
  %c = call i32 @close(i32 %d)
  ret void
fill:
  %o = call i32 (ptr, i32, ...) @open(ptr @dev_null, i32 %flags)
  ret void
}

define internal ptr @run(ptr %unused) noinline {
entry:
  %sz = load i64, ptr @stack_bytes
  %st = call i64 @l0_rt_run(i64 %sz)
  store i64 %st, ptr @exit_status
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
  call void @host_setup()
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
