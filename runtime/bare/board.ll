; board.ll -- the part of a board's host, spec section 9.2's host without an
; operating system, that no machine decides: every l0_host_ function
; runtime/l0rt.ll calls (spec section 10.3) that neither the CPU nor the
; board needs to say anything about. It carries no triple, like l0rt.ll, and
; is linked with an architecture's part, runtime/arch/ARCH/boot.ll, which
; boots the CPU and calls @l0_bare_main; a board's part,
; runtime/board/BOARD.ll, which says what the board has and where; the
; drivers in runtime/dev/ that the board's part drives its devices with;
; runtime/freestanding.ll, the allocator over the heap and the mem
; functions; and the board's layout, runtime/board/BOARD.ld. The parts a
; target links are listed by its manifest, runtime/targets/TARGET.
;
; What it gives:
;   - standard input, the bytes the firmware loaded as an initrd, which the
;     device tree's /chosen says the place of, or else the bytes a loader
;     put at __input_start, their count in the word at __input_len, read
;     once at boot, since a serial line has no end of input; a board whose
;     layout has no loader's word, and whose firmware loads no initrd, has
;     none;
;     standard output, the board's console; standard error and the exit
;     status, the board's to deliver
;   - no files and no environment, as section 9.2 says
;   - the arguments, the device tree's /chosen/bootargs, split at runs of
;     spaces
;   - regions over the board's table of devices, and the barrier the CPU's
;   - user mode: the pool of frames, the RAM the device tree describes in
;     the windows the board's part gives, the spaces, and the tables mapping their user range, written through
;     the CPU's descriptors: three levels of 4 KB tables with 9-bit
;     indices, which arm64's 4 KB granule and RISC-V's Sv39 both are
;   - the interrupts' bookkeeping, over the board's controller, and the
;     clock and timer, over the CPU's counter
;
; The hooks each other part defines are declared below, by the part.

; Defined by runtime/l0rt.ll. Spec section 10.3.
declare i64 @l0_rt_run(i64)

; Defined by runtime/freestanding.ll.
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)

; The board's layout, runtime/board/BOARD.ld. A layout whose board has no
; loader puts __input_len at a word that is always 0, so that there is no
; input unless the firmware loads an initrd.
@__stack_top = external global i8
@__stack_bottom = external global i8
@__input_len = external global i64
@__input_start = external global i8
@__heap_start = external global i8

; The architecture's part, runtime/arch/ARCH/boot.ll.
declare i64 @l0_arch_counter()
declare i64 @l0_arch_counter_hz()
declare void @l0_arch_timer_set(i64)
declare void @l0_arch_timer_off()
declare void @l0_arch_barrier()
declare void @l0_arch_wait()
declare void @l0_arch_code_sync(i64, i64)
declare void @l0_arch_dma_sync(i64, i64, i64)
declare i64 @l0_arch_pte_table(i64)
declare i64 @l0_arch_pte_page(i64, i64)
declare i64 @l0_arch_pte_device(i64)
declare i64 @l0_arch_pte_pa(i64)
declare void @l0_arch_tables_written()
declare void @l0_arch_mapped(i64)
declare void @l0_arch_tlb_page(i64, i64)
declare void @l0_arch_space_leave()
declare void @l0_arch_user_run(ptr, i64, i64)

; The board's part, runtime/board/BOARD.ll.
declare void @l0_board_init(i64, i64)
declare void @l0_board_console_put(i8)
declare i64 @l0_board_err_write(ptr, i64)
declare void @l0_board_exit(i64) noreturn
declare i64 @l0_board_device_count()
declare i64 @l0_board_device_base(i64)
declare i64 @l0_board_device_len(i64)
declare void @l0_board_space_init(i64, i64)
declare i64 @l0_board_window_count()
declare i64 @l0_board_window_start(i64)
declare i64 @l0_board_window_end(i64)
declare void @l0_board_map_ram(i64, i64)
declare i1 @l0_board_irq_exists(i64)
declare void @l0_board_irq_enable(i64)
declare i64 @l0_board_irq_take()
declare void @l0_board_irq_end(i64)

; ------------------------------------------------------------------- entry

; Called by the architecture's boot code, on the boot stack, with the
; device tree's address and the booting CPU's number. The arguments and
; the place of standard input are copied out of the tree before anything
; else, since the tree is wherever the firmware put it, and the pool is
; built from it and from standard input's count. l0_rt_run's frame is a
; little below the top, so the size it is given leaves 64 KB for what lies
; above it.
define void @l0_bare_main(i64 %dtb, i64 %hart) noreturn {
entry:
  call void @boot_args(i64 %dtb)
  call void @input_init()
  call void @pool_init(i64 %dtb)
  call void @l0_board_init(i64 %dtb, i64 %hart)
  %top = ptrtoint ptr @__stack_top to i64
  %bottom = ptrtoint ptr @__stack_bottom to i64
  %all = sub i64 %top, %bottom
  %size = sub i64 %all, 65536
  %st = call i64 @l0_rt_run(i64 %size)
  call void @l0_host_exit(i64 %st)
  unreachable
}

define void @l0_host_exit(i64 %status) noreturn {
entry:
  call void @l0_board_exit(i64 %status)
  unreachable
}

; Pages freestanding.ll's allocator has freed: a board has no kernel to
; give them to, and they stay the heap's.
define void @l0_heap_release(i64 %base, i64 %len) {
entry:
  ret void
}

@hexd = private constant [16 x i8] c"0123456789abcdef"

; Writes v on standard error as 0x and 16 hex digits, for the architecture's
; report of an exception the runtime did not expect.
define void @l0_bare_put_hex(i64 %v) {
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

; ----------------------------------------------------------------- streams

@in_pos = internal global i64 0
@in_len = internal global i64 0
@in_start = internal global i64 0
@initrd_lo = internal global i64 0
@initrd_hi = internal global i64 0

; Finds standard input's place and count once, before the program starts,
; since the page holding the loader's count is the pool's from then on. An
; initrd the device tree describes, from initrd_lo to initrd_hi, wins if it
; lies below the heap, which is where the pool's first window ends; if
; not, the loader's bytes at __input_start, at most what the window up to
; the heap holds; with neither, there is no input.
define internal void @input_init() {
entry:
  %lo = load i64, ptr @initrd_lo
  %hi = load i64, ptr @initrd_hi
  %hs = ptrtoint ptr @__heap_start to i64
  %some = icmp ult i64 %lo, %hi
  %below = icmp ule i64 %hi, %hs
  %initrd = and i1 %some, %below
  br i1 %initrd, label %fromtree, label %loader
fromtree:
  %n0 = sub i64 %hi, %lo
  store i64 %lo, ptr @in_start
  store i64 %n0, ptr @in_len
  ret void
loader:
  %is = ptrtoint ptr @__input_start to i64
  %len = load i64, ptr @__input_len
  %fits = icmp ult i64 %is, %hs
  %room0 = sub i64 %hs, %is
  %room = select i1 %fits, i64 %room0, i64 0
  %big = icmp ugt i64 %len, %room
  %n = select i1 %big, i64 %room, i64 %len
  store i64 %is, ptr @in_start
  store i64 %n, ptr @in_len
  ret void
}

; Once a read reaches the input's last byte, no read can give its bytes
; again, and their pages join the pool.
define i64 @l0_host_read(i64 %s, ptr %buf, i64 %n) {
entry:
  %is0 = icmp eq i64 %s, 0
  br i1 %is0, label %input, label %bad
bad:
  ret i64 -5
input:
  %len = load i64, ptr @in_len
  %pos = load i64, ptr @in_pos
  %left = sub i64 %len, %pos
  %less = icmp ult i64 %left, %n
  %k = select i1 %less, i64 %left, i64 %n
  %base = load i64, ptr @in_start
  %at = add i64 %base, %pos
  %src = inttoptr i64 %at to ptr
  %x = call ptr @memcpy(ptr %buf, ptr %src, i64 %k)
  %np = add i64 %pos, %k
  store i64 %np, ptr @in_pos
  %end = icmp eq i64 %np, %len
  br i1 %end, label %join, label %out
join:
  call void @input_join()
  br label %out
out:
  ret i64 %k
}

define i64 @l0_host_write(i64 %s, ptr %buf, i64 %n) {
entry:
  %is1 = icmp eq i64 %s, 1
  br i1 %is1, label %out, label %not1
not1:
  %is2 = icmp eq i64 %s, 2
  br i1 %is2, label %err, label %bad
bad:
  ret i64 -5
out:
  br label %loop
loop:
  %i = phi i64 [ 0, %out ], [ %i1, %body ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr i8, ptr %buf, i64 %i
  %c = load i8, ptr %p
  call void @l0_board_console_put(i8 %c)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %n
err:
  %r = call i64 @l0_board_err_write(ptr %buf, i64 %n)
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

define ptr @l0_host_setting(ptr %name) {
entry:
  ret ptr null
}

; ------------------------------------------------------- the clock, timer

; The CPU's counter, at l0_arch_counter_hz counts a second, in seconds and
; then nanoseconds, so that the product cannot overflow.
define i64 @l0_host_clock_ns() {
entry:
  %cnt = call i64 @l0_arch_counter()
  %frq = call i64 @l0_arch_counter_hz()
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

; The counter's value for t nanoseconds, rounded up, so that the timer
; fires no earlier than clock_ns reads t; a negative t puts it off.
define i64 @l0_host_timer_at(i64 %t) {
entry:
  %off = icmp slt i64 %t, 0
  br i1 %off, label %disarm, label %arm
disarm:
  call void @l0_arch_timer_off()
  ret i64 0
arm:
  %frq = call i64 @l0_arch_counter_hz()
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
  call void @l0_arch_timer_set(i64 %cval)
  ret i64 0
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
@s_initrd_start = private constant [19 x i8] c"linux,initrd-start\00"
@s_initrd_end = private constant [17 x i8] c"linux,initrd-end\00"

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

; The number in the len bytes at val, one cell or, for two or more, its
; last two as an address of two cells, or 0 if there is not a whole cell.
define internal i64 @dt_prop_num(i64 %val, i64 %len) {
entry:
  %cells = lshr i64 %len, 2
  %none = icmp eq i64 %cells, 0
  br i1 %none, label %zero, label %num
zero:
  ret i64 0
num:
  %n = call i64 @dt_cells(i64 %val, i64 %cells)
  ret i64 %n
}

; Finds /chosen's bootargs in the device tree at dtb, if there is one, and
; takes the arguments from it, and its linux,initrd-start and -end, where
; the firmware says it loaded an initrd, for standard input.
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
  br i1 %isargs, label %take, label %nargs
take:
  call void @take_args(i64 %val, i64 %len)
  br label %prop
nargs:
  %isrs = call i1 @dt_name_is(i64 %pname, ptr @s_initrd_start)
  br i1 %isrs, label %takers, label %nstart
takers:
  %rs = call i64 @dt_prop_num(i64 %val, i64 %len)
  store i64 %rs, ptr @initrd_lo
  br label %prop
nstart:
  %isre = call i1 @dt_name_is(i64 %pname, ptr @s_initrd_end)
  br i1 %isre, label %takere, label %prop
takere:
  %re = call i64 @dt_prop_num(i64 %val, i64 %len)
  store i64 %re, ptr @initrd_hi
  br label %prop
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

; ----------------------------------------------------------------- regions

; base and len are checked by l0rt.ll: len at least 1, base not negative. A
; region is any range wholly within one of the board's devices, at the
; address the device has, which the boot map makes device memory.
define i64 @l0_host_region(i64 %base, i64 %len) {
entry:
  %end = add i64 %base, %len
  %count = call i64 @l0_board_device_count()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %count
  br i1 %more, label %look, label %none
look:
  %db = call i64 @l0_board_device_base(i64 %i)
  %dl = call i64 @l0_board_device_len(i64 %i)
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

; A region is the device's own address, so nothing was mapped for it.
define void @l0_host_region_close(i64 %addr, i64 %len) {
entry:
  ret void
}

define void @l0_host_barrier() {
entry:
  call void @l0_arch_barrier()
  ret void
}

; --------------------------------------------------------------- user mode
;
; Spec sections 6.13 and 10.3. Pages come from the pool, built at boot by
; pool_init in at most 32 pieces of whole pages, mapped where they are by
; the boot map: each of the windows the board's part gives, cut by the RAM
; the device tree's /memory nodes describe, with the device tree and the
; pages holding standard input's bytes cut out, those pages then pieces of
; their own after the others. Firmware reservations are not read, since a
; board's windows leave them out. Pages are numbered through the pieces in
; order, and frame k is the k-th page; page_state, at the start of the first
; piece large enough, holds 4 bytes for every page, so the pool has no bound
; but the RAM.
;
; Untouched pages of the pieces before the input's go to frames from the
; bottom and to the host's own page tables from the top, until the two
; meet; a page given back, frame or table, goes on one free list, threaded
; through the pages' first words, which both take from first, and the
; input's pages join it once a read of standard input has reached its end.
; pool_left counts the pages either can still take. page_state says what
; each page is: 0 free or a table, and k from 1 a frame mapped k - 1 times.
; A space is
; an index into sp_l1, its root table, or 0 once freed, and its ASID is the
; index plus 1, so the 255 spaces have 255 ASIDs and moving between them
; flushes nothing; a slot freed is given again, its ASID with it, so
; space_free flushes the TLB.
;
; Each space's root table maps what the board's boot map does, for the
; host alone, since the host runs on the thread's tables between traps, and
; its 4th entry, the user range, 0xC0000000 up to 0x100000000, through a
; table of its own, whose entries are tables of 4 KB pages made as pages
; are mapped. Every user page is tagged with the space's ASID. A leaf maps
; a frame when its address is in the pool, and a device's page otherwise.

@pool_lo = internal global i64 0
@pool_hi = internal global i64 0
@pool_free = internal global i64 0
@pool_boot = internal global i64 0                  ; pages before the input's
@pool_all = internal global i64 0                   ; every page, the input's too
@pool_left = internal global i64 0
@page_state = internal global i64 0                 ; its address
@pc_start = internal global [32 x i64] zeroinitializer
@pc_pages = internal global [32 x i64] zeroinitializer
@pc_first = internal global [32 x i64] zeroinitializer
@pc_n = internal global i64 0
@pc_boot_n = internal global i64 0                  ; pieces before the input's
@ram_lo = internal global [8 x i64] zeroinitializer
@ram_hi = internal global [8 x i64] zeroinitializer
@ram_n = internal global i64 0
@hole_lo = internal global [2 x i64] zeroinitializer
@hole_hi = internal global [2 x i64] zeroinitializer
@in_joined = internal global i1 false
@sp_l1 = internal global [255 x i64] zeroinitializer
@sp_count = internal global i64 0
@s_memory = private constant [7 x i8] c"memory\00"
@s_reg = private constant [4 x i8] c"reg\00"
@s_acells = private constant [15 x i8] c"#address-cells\00"
@s_scells = private constant [12 x i8] c"#size-cells\00"

define internal i64 @page_up(i64 %a) {
entry:
  %b = add i64 %a, 4095
  %r = and i64 %b, -4096
  ret i64 %r
}

; The device tree's size, or 0 if there is none at dtb.
define internal i64 @dt_size(i64 %dtb) {
entry:
  %null = icmp eq i64 %dtb, 0
  br i1 %null, label %none, label %magic
magic:
  %m = call i64 @be32(i64 %dtb)
  %ok = icmp eq i64 %m, 3490578157                          ; 0xd00dfeed
  br i1 %ok, label %size, label %none
size:
  %ta = add i64 %dtb, 4
  %total = call i64 @be32(i64 %ta)
  ret i64 %total
none:
  ret i64 0
}

; Whether the NUL-terminated name at a is memory, or memory@ and a unit
; address.
define internal i1 @dt_is_memory(i64 %a) {
entry:
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k1, %same ]
  %sp = getelementptr i8, ptr @s_memory, i64 %k
  %t8 = load i8, ptr %sp
  %t = zext i8 %t8 to i64
  %ak = add i64 %a, %k
  %c = call i64 @dt_byte(i64 %ak)
  %last = icmp eq i64 %t, 0
  br i1 %last, label %term, label %cmp
cmp:
  %eq = icmp eq i64 %c, %t
  br i1 %eq, label %same, label %no
same:
  %k1 = add i64 %k, 1
  br label %loop
term:
  %nul = icmp eq i64 %c, 0
  %at = icmp eq i64 %c, 64
  %r = or i1 %nul, %at
  ret i1 %r
no:
  ret i1 false
}

; The number in n cells at a, n 1 or 2, or the last two of more.
define internal i64 @dt_cells(i64 %a, i64 %n) {
entry:
  %one = icmp eq i64 %n, 1
  br i1 %one, label %w1, label %w2
w1:
  %v1 = call i64 @be32(i64 %a)
  ret i64 %v1
w2:
  %n2 = sub i64 %n, 2
  %o = shl i64 %n2, 2
  %hi_a = add i64 %a, %o
  %lo_a = add i64 %hi_a, 4
  %hi = call i64 @be32(i64 %hi_a)
  %lo = call i64 @be32(i64 %lo_a)
  %hs = shl i64 %hi, 32
  %v2 = or i64 %hs, %lo
  ret i64 %v2
}

; Records the ranges of a memory node's reg, len bytes at val, each an
; address of ac cells and a size of sc cells, at most 8 in all.
define internal void @take_ram(i64 %val, i64 %len, i64 %ac, i64 %sc) {
entry:
  %cells = add i64 %ac, %sc
  %stride = shl i64 %cells, 2
  %none = icmp eq i64 %stride, 0
  %noaddr = icmp eq i64 %ac, 0
  %nosize = icmp eq i64 %sc, 0
  %bad0 = or i1 %none, %noaddr
  %bad = or i1 %bad0, %nosize
  br i1 %bad, label %done, label %loop
loop:
  %off = phi i64 [ 0, %entry ], [ %next, %step ]
  %next = add i64 %off, %stride
  %fits = icmp ule i64 %next, %len
  br i1 %fits, label %one, label %done
one:
  %a = add i64 %val, %off
  %base = call i64 @dt_cells(i64 %a, i64 %ac)
  %ao = shl i64 %ac, 2
  %sa = add i64 %a, %ao
  %size = call i64 @dt_cells(i64 %sa, i64 %sc)
  %n = load i64, ptr @ram_n
  %room = icmp ult i64 %n, 8
  br i1 %room, label %keep, label %step
keep:
  %lp = getelementptr [8 x i64], ptr @ram_lo, i64 0, i64 %n
  store i64 %base, ptr %lp
  %end = add i64 %base, %size
  %hp = getelementptr [8 x i64], ptr @ram_hi, i64 0, i64 %n
  store i64 %end, ptr %hp
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @ram_n
  br label %step
step:
  br label %loop
done:
  ret void
}

; Finds the RAM the device tree at dtb describes: the reg of each node
; under the root named memory, its cells as the root's #address-cells and
; #size-cells say, 2 and 1 if it does not. The tree is read as boot_args
; reads it.
define internal void @boot_memory(i64 %dtb) {
entry:
  %total = call i64 @dt_size(i64 %dtb)
  %null = icmp eq i64 %total, 0
  br i1 %null, label %done, label %head
head:
  %sa = add i64 %dtb, 8
  %ostruct = call i64 @be32(i64 %sa)
  %na = add i64 %dtb, 12
  %ostr = call i64 @be32(i64 %na)
  %p0 = add i64 %dtb, %ostruct
  %end = add i64 %dtb, %total
  %strings = add i64 %dtb, %ostr
  br label %loop
loop:
  %p = phi i64 [ %p0, %head ], [ %bp, %begin ], [ %ep, %endnode ], [ %pp, %next ], [ %np, %nop ]
  %depth = phi i64 [ 0, %head ], [ %bd, %begin ], [ %ed, %endnode ], [ %depth, %next ], [ %depth, %nop ]
  %in = phi i1 [ false, %head ], [ %bin, %begin ], [ %ein, %endnode ], [ %in, %next ], [ %in, %nop ]
  %ac = phi i64 [ 2, %head ], [ %ac, %begin ], [ %ac, %endnode ], [ %ac2, %next ], [ %ac, %nop ]
  %sc = phi i64 [ 1, %head ], [ %sc, %begin ], [ %sc, %endnode ], [ %sc2, %next ], [ %sc, %nop ]
  %over = icmp uge i64 %p, %end
  br i1 %over, label %done, label %token
token:
  %tok = call i64 @be32(i64 %p)
  switch i64 %tok, label %done [ i64 1, label %begin
                                 i64 2, label %endnode
                                 i64 3, label %prop
                                 i64 4, label %nop ]
begin:
  %name = add i64 %p, 4
  %top = icmp eq i64 %depth, 1
  %np8 = inttoptr i64 %name to ptr
  %nlen = call i64 @strlen(ptr %np8)
  %ismem = call i1 @dt_is_memory(i64 %name)
  %mem = and i1 %top, %ismem
  %bin = or i1 %in, %mem
  %nl1 = add i64 %nlen, 1
  %npad = call i64 @pad4(i64 %nl1)
  %bp0 = add i64 %p, 4
  %bp = add i64 %bp0, %npad
  %bd = add i64 %depth, 1
  br label %loop
endnode:
  %leaving = icmp eq i64 %depth, 2
  %ein = select i1 %leaving, i1 false, i1 %in
  %ep = add i64 %p, 4
  %ed = sub i64 %depth, 1
  br label %loop
prop:
  %la = add i64 %p, 4
  %len = call i64 @be32(i64 %la)
  %oa = add i64 %p, 8
  %noff = call i64 @be32(i64 %oa)
  %val = add i64 %p, 12
  %pname = add i64 %strings, %noff
  %root = icmp eq i64 %depth, 1
  br i1 %root, label %rootprop, label %notroot
rootprop:
  %isac = call i1 @dt_name_is(i64 %pname, ptr @s_acells)
  %issc = call i1 @dt_name_is(i64 %pname, ptr @s_scells)
  %v = call i64 @be32(i64 %val)
  %ac1 = select i1 %isac, i64 %v, i64 %ac
  %sc1 = select i1 %issc, i64 %v, i64 %sc
  br label %next
notroot:
  %d2 = icmp eq i64 %depth, 2
  %ours = and i1 %in, %d2
  br i1 %ours, label %memprop, label %next
memprop:
  %isreg = call i1 @dt_name_is(i64 %pname, ptr @s_reg)
  br i1 %isreg, label %takereg, label %next
takereg:
  call void @take_ram(i64 %val, i64 %len, i64 %ac, i64 %sc)
  br label %next
next:
  %ac2 = phi i64 [ %ac1, %rootprop ], [ %ac, %notroot ], [ %ac, %memprop ], [ %ac, %takereg ]
  %sc2 = phi i64 [ %sc1, %rootprop ], [ %sc, %notroot ], [ %sc, %memprop ], [ %sc, %takereg ]
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

; Adds the pages a to b as a piece, if fewer than 32 are made.
define internal void @add_piece(i64 %a, i64 %b) {
entry:
  %n = load i64, ptr @pc_n
  %room = icmp ult i64 %n, 32
  br i1 %room, label %put, label %done
put:
  %sp = getelementptr [32 x i64], ptr @pc_start, i64 0, i64 %n
  store i64 %a, ptr %sp
  %bytes = sub i64 %b, %a
  %pages = lshr i64 %bytes, 12
  %pp = getelementptr [32 x i64], ptr @pc_pages, i64 0, i64 %n
  store i64 %pages, ptr %pp
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @pc_n
  br label %done
done:
  ret void
}

; Adds the pages a to b as pieces, with holes h and after cut out.
define internal void @cut(i64 %a, i64 %b, i64 %h) {
entry:
  %empty = icmp uge i64 %a, %b
  br i1 %empty, label %done, label %which
which:
  %last = icmp eq i64 %h, 2
  br i1 %last, label %add, label %hole
add:
  call void @add_piece(i64 %a, i64 %b)
  ret void
hole:
  %lp = getelementptr [2 x i64], ptr @hole_lo, i64 0, i64 %h
  %lo = load i64, ptr %lp
  %hp = getelementptr [2 x i64], ptr @hole_hi, i64 0, i64 %h
  %hi = load i64, ptr %hp
  %h1 = add i64 %h, 1
  %nothing = icmp uge i64 %lo, %hi
  %before = icmp ule i64 %hi, %a
  %after = icmp uge i64 %lo, %b
  %c0 = or i1 %nothing, %before
  %clear = or i1 %c0, %after
  br i1 %clear, label %whole, label %split
whole:
  call void @cut(i64 %a, i64 %b, i64 %h1)
  ret void
split:
  call void @cut(i64 %a, i64 %lo, i64 %h1)
  call void @cut(i64 %hi, i64 %b, i64 %h1)
  ret void
done:
  ret void
}

; Adds the whole pages of a to b that are RAM, as pieces, with the holes
; cut out if cut is true.
define internal void @ram_add(i64 %a, i64 %b, i1 %cut) {
entry:
  %n = load i64, ptr @ram_n
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %look, label %done
look:
  %lp = getelementptr [8 x i64], ptr @ram_lo, i64 0, i64 %i
  %rl = load i64, ptr %lp
  %hp = getelementptr [8 x i64], ptr @ram_hi, i64 0, i64 %i
  %rh = load i64, ptr %hp
  %up = icmp ugt i64 %a, %rl
  %lo0 = select i1 %up, i64 %a, i64 %rl
  %down = icmp ult i64 %b, %rh
  %hi0 = select i1 %down, i64 %b, i64 %rh
  %lo = call i64 @page_up(i64 %lo0)
  %hi = and i64 %hi0, -4096
  %some = icmp ult i64 %lo, %hi
  br i1 %some, label %add, label %next
add:
  br i1 %cut, label %c, label %p
c:
  call void @cut(i64 %lo, i64 %hi, i64 0)
  br label %next
p:
  call void @add_piece(i64 %lo, i64 %hi)
  br label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

; Tells the board's part each range of RAM the device tree describes, so
; that it maps what is there and nothing else. The ranges are in ram_lo and
; ram_hi, ram_n of them.
define internal void @map_ram() {
entry:
  %n = load i64, ptr @ram_n
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %lp = getelementptr [8 x i64], ptr @ram_lo, i64 0, i64 %i
  %lo = load i64, ptr %lp
  %hp = getelementptr [8 x i64], ptr @ram_hi, i64 0, i64 %i
  %hi = load i64, ptr %hp
  call void @l0_board_map_ram(i64 %lo, i64 %hi)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

; Builds the pool: the windows' RAM with the device tree and the input's
; pages cut out, then the input's pages, which lie in the first window on
; every board, then the numbering.
define internal void @pool_init(i64 %dtb) {
entry:
  call void @boot_memory(i64 %dtb)
  call void @map_ram()
  %dsize = call i64 @dt_size(i64 %dtb)
  %dlo = and i64 %dtb, -4096
  %de = add i64 %dtb, %dsize
  %dhi = call i64 @page_up(i64 %de)
  store i64 %dlo, ptr @hole_lo
  store i64 %dhi, ptr @hole_hi
  %is = load i64, ptr @in_start
  %len = load i64, ptr @in_len
  %ie0 = add i64 %is, %len
  %ie = call i64 @page_up(i64 %ie0)
  %h1l = getelementptr [2 x i64], ptr @hole_lo, i64 0, i64 1
  store i64 %is, ptr %h1l
  %h1h = getelementptr [2 x i64], ptr @hole_hi, i64 0, i64 1
  store i64 %ie, ptr %h1h
  %wn = call i64 @l0_board_window_count()
  br label %wloop
wloop:
  %w = phi i64 [ 0, %entry ], [ %w1, %wbody ]
  %wmore = icmp ult i64 %w, %wn
  br i1 %wmore, label %wbody, label %input
wbody:
  %ws = call i64 @l0_board_window_start(i64 %w)
  %we = call i64 @l0_board_window_end(i64 %w)
  call void @ram_add(i64 %ws, i64 %we, i1 true)
  %w1 = add i64 %w, 1
  br label %wloop
input:
  %nb = load i64, ptr @pc_n
  store i64 %nb, ptr @pc_boot_n
  call void @ram_add(i64 %is, i64 %ie, i1 false)
  call void @pool_number()
  ret void
}

; Takes page_state's pages from the front of the first piece before the
; input's that holds them, numbers the pages, and zeroes page_state. With
; no such piece, the pool is empty.
define internal void @pool_number() {
entry:
  %n = load i64, ptr @pc_n
  br label %sum
sum:
  %i = phi i64 [ 0, %entry ], [ %i1, %sbody ]
  %t = phi i64 [ 0, %entry ], [ %t1, %sbody ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %sbody, label %need
sbody:
  %pgp = getelementptr [32 x i64], ptr @pc_pages, i64 0, i64 %i
  %pg = load i64, ptr %pgp
  %t1 = add i64 %t, %pg
  %i1 = add i64 %i, 1
  br label %sum
need:
  %b4 = shl i64 %t, 2
  %b4u = add i64 %b4, 4095
  %s = lshr i64 %b4u, 12
  %nb = load i64, ptr @pc_boot_n
  br label %find
find:
  %j = phi i64 [ 0, %need ], [ %j1, %fnext ]
  %fmore = icmp ult i64 %j, %nb
  br i1 %fmore, label %flook, label %none
flook:
  %pjp = getelementptr [32 x i64], ptr @pc_pages, i64 0, i64 %j
  %pj = load i64, ptr %pjp
  %big = icmp uge i64 %pj, %s
  br i1 %big, label %take, label %fnext
fnext:
  %j1 = add i64 %j, 1
  br label %find
none:
  store i64 0, ptr @pc_n
  store i64 0, ptr @pc_boot_n
  ret void
take:
  %sjp = getelementptr [32 x i64], ptr @pc_start, i64 0, i64 %j
  %sj = load i64, ptr %sjp
  store i64 %sj, ptr @page_state
  %so = shl i64 %s, 12
  %sj1 = add i64 %sj, %so
  store i64 %sj1, ptr %sjp
  %pj1 = sub i64 %pj, %s
  store i64 %pj1, ptr %pjp
  br label %number
number:
  %k = phi i64 [ 0, %take ], [ %k1, %nbody ]
  %acc = phi i64 [ 0, %take ], [ %acc1, %nbody ]
  %boot = phi i64 [ 0, %take ], [ %boot1, %nbody ]
  %nmore = icmp ult i64 %k, %n
  br i1 %nmore, label %nbody, label %finish
nbody:
  %fp = getelementptr [32 x i64], ptr @pc_first, i64 0, i64 %k
  store i64 %acc, ptr %fp
  %isb = icmp eq i64 %k, %nb
  %boot1 = select i1 %isb, i64 %acc, i64 %boot
  %pkp = getelementptr [32 x i64], ptr @pc_pages, i64 0, i64 %k
  %pk = load i64, ptr %pkp
  %acc1 = add i64 %acc, %pk
  %k1 = add i64 %k, 1
  br label %number
finish:
  %hasin = icmp ult i64 %nb, %n
  %bootv = select i1 %hasin, i64 %boot, i64 %acc
  store i64 %acc, ptr @pool_all
  store i64 %bootv, ptr @pool_boot
  store i64 %bootv, ptr @pool_left
  %bytes = shl i64 %acc, 2
  %st = inttoptr i64 %sj to ptr
  call void @llvm.memset.p0.i64(ptr %st, i8 0, i64 %bytes, i1 false)
  ret void
}

; Gives the input's pages to the free list, once, from the last, so the
; first is taken first.
define internal void @input_join() {
entry:
  %j = load i1, ptr @in_joined
  br i1 %j, label %done, label %go
go:
  store i1 true, ptr @in_joined
  %all = load i64, ptr @pool_all
  %boot = load i64, ptr @pool_boot
  br label %loop
loop:
  %k = phi i64 [ %all, %go ], [ %k0, %give ]
  %more = icmp ugt i64 %k, %boot
  br i1 %more, label %give, label %done
give:
  %k0 = sub i64 %k, 1
  call void @page_give(i64 %k0)
  br label %loop
done:
  ret void
}

; How many pages the pieces before the input's have.
define internal i64 @pool_pages() {
entry:
  %n = load i64, ptr @pool_boot
  ret i64 %n
}

; The address of page k, below pool_all.
define internal i64 @page_addr(i64 %k) {
entry:
  %n = load i64, ptr @pc_n
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %look, label %none
look:
  %fp = getelementptr [32 x i64], ptr @pc_first, i64 0, i64 %i
  %f = load i64, ptr %fp
  %pp = getelementptr [32 x i64], ptr @pc_pages, i64 0, i64 %i
  %pg = load i64, ptr %pp
  %e = add i64 %f, %pg
  %in = icmp ult i64 %k, %e
  br i1 %in, label %found, label %next
found:
  %sp = getelementptr [32 x i64], ptr @pc_start, i64 0, i64 %i
  %s = load i64, ptr %sp
  %d = sub i64 %k, %f
  %o = shl i64 %d, 12
  %pa = add i64 %s, %o
  ret i64 %pa
next:
  %i1 = add i64 %i, 1
  br label %loop
none:
  ret i64 0
}

; The pool's index of the page at pa, or -1 if pa is not in the pool.
define internal i64 @page_of(i64 %pa) {
entry:
  %n = load i64, ptr @pc_n
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %look, label %no
look:
  %sp = getelementptr [32 x i64], ptr @pc_start, i64 0, i64 %i
  %s = load i64, ptr %sp
  %pp = getelementptr [32 x i64], ptr @pc_pages, i64 0, i64 %i
  %pg = load i64, ptr %pp
  %len = shl i64 %pg, 12
  %e = add i64 %s, %len
  %lo = icmp uge i64 %pa, %s
  %hi = icmp ult i64 %pa, %e
  %in = and i1 %lo, %hi
  br i1 %in, label %yes, label %next
yes:
  %fp = getelementptr [32 x i64], ptr @pc_first, i64 0, i64 %i
  %f = load i64, ptr %fp
  %o = sub i64 %pa, %s
  %d = lshr i64 %o, 12
  %k = add i64 %f, %d
  ret i64 %k
next:
  %i1 = add i64 %i, 1
  br label %loop
no:
  ret i64 -1
}

; The index of a page of the pool, not yet zeroed: a freed one if any,
; else an untouched one from the top if top, from the bottom if not; or -1
; when none is left.
define internal i64 @page_take(i1 %top) {
entry:
  %k = call i64 @page_find(i1 %top)
  %got = icmp sge i64 %k, 0
  br i1 %got, label %count, label %done
count:
  %l = load i64, ptr @pool_left
  %l1 = sub i64 %l, 1
  store i64 %l1, ptr @pool_left
  br label %done
done:
  ret i64 %k
}

define internal i64 @page_find(i1 %top) {
entry:
  %f = load i64, ptr @pool_free
  %have = icmp ne i64 %f, 0
  br i1 %have, label %reuse, label %fresh
reuse:
  %k = sub i64 %f, 1
  %pa = call i64 @page_addr(i64 %k)
  %pq = inttoptr i64 %pa to ptr
  %next = load i64, ptr %pq
  store i64 %next, ptr @pool_free
  ret i64 %k
fresh:
  %lo = load i64, ptr @pool_lo
  %hi = load i64, ptr @pool_hi
  %used = add i64 %lo, %hi
  %all = call i64 @pool_pages()
  %room = icmp ult i64 %used, %all
  br i1 %room, label %which, label %none
which:
  br i1 %top, label %high, label %low
high:
  %hi1 = add i64 %hi, 1
  store i64 %hi1, ptr @pool_hi
  %kh = sub i64 %all, %hi1
  ret i64 %kh
low:
  %lo1 = add i64 %lo, 1
  store i64 %lo1, ptr @pool_lo
  ret i64 %lo
none:
  ret i64 -1
}

; Puts page k on the free list.
define internal void @page_give(i64 %k) {
entry:
  %pa = call i64 @page_addr(i64 %k)
  %pq = inttoptr i64 %pa to ptr
  %f = load i64, ptr @pool_free
  store i64 %f, ptr %pq
  %k1 = add i64 %k, 1
  store i64 %k1, ptr @pool_free
  %l = load i64, ptr @pool_left
  %l1 = add i64 %l, 1
  store i64 %l1, ptr @pool_left
  ret void
}

; Gives back the table page at pa.
define internal void @table_give(i64 %pa) {
entry:
  %k = call i64 @page_of(i64 %pa)
  call void @page_give(i64 %k)
  ret void
}

define internal ptr @state_of(i64 %k) {
entry:
  %b = load i64, ptr @page_state
  %o = shl i64 %k, 2
  %a = add i64 %b, %o
  %p = inttoptr i64 %a to ptr
  ret ptr %p
}

; Counts one mapping more, or one fewer for a negative by, of the frame a
; leaf d maps, if it maps one rather than a device's page.
define internal void @frame_mapped(i64 %d, i32 %by) {
entry:
  %pa = call i64 @l0_arch_pte_pa(i64 %d)
  %k = call i64 @page_of(i64 %pa)
  %frame = icmp sge i64 %k, 0
  br i1 %frame, label %count, label %done
count:
  %sp = call ptr @state_of(i64 %k)
  %s = load i32, ptr %sp
  %s1 = add i32 %s, %by
  store i32 %s1, ptr %sp
  br label %done
done:
  ret void
}

define internal void @zero_page(i64 %pa) {
entry:
  %p = inttoptr i64 %pa to ptr
  call void @llvm.memset.p0.i64(ptr align 4096 %p, i8 0, i64 4096, i1 false)
  ret void
}

; A zeroed page for a table, or 0 when none is left.
define internal i64 @pool_page() {
entry:
  %k = call i64 @page_take(i1 true)
  %none = icmp slt i64 %k, 0
  br i1 %none, label %out, label %take
out:
  ret i64 0
take:
  %pa = call i64 @page_addr(i64 %k)
  call void @zero_page(i64 %pa)
  ret i64 %pa
}

define i64 @l0_host_frame_new() {
entry:
  %k = call i64 @page_take(i1 false)
  %none = icmp slt i64 %k, 0
  br i1 %none, label %out, label %take
out:
  ret i64 -5
take:
  %sp = call ptr @state_of(i64 %k)
  store i32 1, ptr %sp
  %pa = call i64 @page_addr(i64 %k)
  call void @zero_page(i64 %pa)
  ret i64 %k
}

; 2 if f is not a frame, 9 if a space maps it, else 0, once it is free.
define i64 @l0_host_frame_free(i64 %f) {
entry:
  %pa = call i64 @frame_pa(i64 %f)
  %nof = icmp eq i64 %pa, 0
  br i1 %nof, label %e2, label %check
check:
  %sp = call ptr @state_of(i64 %f)
  %s = load i32, ptr %sp
  %mapped = icmp ugt i32 %s, 1
  br i1 %mapped, label %e9, label %give
give:
  store i32 0, ptr %sp
  call void @page_give(i64 %f)
  ret i64 0
e2:
  ret i64 2
e9:
  ret i64 9
}

; Section 10.3: a device on the board reaches a frame at its physical
; address, where the host's map holds it too.
define i64 @l0_host_frame_address(i64 %f) {
entry:
  %pa = call i64 @frame_pa(i64 %f)
  %nof = icmp eq i64 %pa, 0
  %r = select i1 %nof, i64 2, i64 %pa
  ret i64 %r
}

; Frame f's 4096 bytes made to agree between the caches and memory, in
; direction dir, 1 to 3, which l0rt.ll has checked, by what the CPU does
; for it; or 2, not a frame.
define i64 @l0_host_frame_sync(i64 %f, i64 %dir) {
entry:
  %pa = call i64 @frame_pa(i64 %f)
  %nof = icmp eq i64 %pa, 0
  br i1 %nof, label %none, label %sync
none:
  ret i64 2
sync:
  call void @l0_arch_dma_sync(i64 %pa, i64 4096, i64 %dir)
  ret i64 0
}

define i64 @l0_host_frame_free_count() {
entry:
  %n = load i64, ptr @pool_left
  ret i64 %n
}

; The physical address of frame f, or 0 if f is not a frame.
define internal i64 @frame_pa(i64 %f) {
entry:
  %all = load i64, ptr @pool_all
  %in = icmp ult i64 %f, %all
  br i1 %in, label %look, label %no
look:
  %sp = call ptr @state_of(i64 %f)
  %s = load i32, ptr %sp
  %frame = icmp ne i32 %s, 0
  br i1 %frame, label %yes, label %no
yes:
  %pa = call i64 @page_addr(i64 %f)
  ret i64 %pa
no:
  ret i64 0
}

; A freed slot below sp_count if there is one, else sp_count.
define internal i64 @space_slot() {
entry:
  %n = load i64, ptr @sp_count
  br label %scan
scan:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %end = icmp eq i64 %i, %n
  br i1 %end, label %none, label %look
look:
  %sp = getelementptr [255 x i64], ptr @sp_l1, i64 0, i64 %i
  %t = load i64, ptr %sp
  %free = icmp eq i64 %t, 0
  br i1 %free, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %scan
found:
  ret i64 %i
none:
  ret i64 %n
}

define i64 @l0_host_space_new() {
entry:
  %n = call i64 @space_slot()
  %full = icmp uge i64 %n, 255
  br i1 %full, label %out, label %l1
l1:
  %t1 = call i64 @pool_page()
  %no1 = icmp eq i64 %t1, 0
  br i1 %no1, label %out, label %l2
l2:
  %t2 = call i64 @pool_page()
  %no2 = icmp eq i64 %t2, 0
  br i1 %no2, label %back, label %fill
back:
  call void @table_give(i64 %t1)
  br label %out
fill:
  call void @l0_board_space_init(i64 %t1, i64 %t2)
  %sp = getelementptr [255 x i64], ptr @sp_l1, i64 0, i64 %n
  store i64 %t1, ptr %sp
  %c = load i64, ptr @sp_count
  %n1 = add i64 %n, 1
  %grew = icmp ugt i64 %n1, %c
  %c1 = select i1 %grew, i64 %n1, i64 %c
  store i64 %c1, ptr @sp_count
  call void @l0_arch_tables_written()
  ret i64 %n
out:
  ret i64 -5
}

; The root table's entry for the user range, its 4th.
define internal ptr @user_entry(i64 %l1) {
entry:
  %e3 = add i64 %l1, 24
  %p3 = inttoptr i64 %e3 to ptr
  ret ptr %p3
}

; Removes the mapping at user page va of space s: 1 if s is not a space, 4
; if va is not a user page, 10 if nothing is mapped there, else 0, once
; the entry is gone from the TLB too. The table of pages stays.
define i64 @l0_host_space_unmap(i64 %s, i64 %va) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %where
where:
  %okv = call i1 @user_page(i64 %va)
  br i1 %okv, label %find, label %e4
find:
  %e = call i64 @l3_entry(i64 %l1, i64 %va, i1 false)
  %notable = icmp eq i64 %e, 0
  br i1 %notable, label %e10, label %look
look:
  %ep = inttoptr i64 %e to ptr
  %d = load i64, ptr %ep
  %none = icmp eq i64 %d, 0
  br i1 %none, label %e10, label %clear
clear:
  call void @frame_mapped(i64 %d, i32 -1)
  store i64 0, ptr %ep
  %asid = add i64 %s, 1
  call void @l0_arch_tlb_page(i64 %asid, i64 %va)
  ret i64 0
e1:
  ret i64 1
e4:
  ret i64 4
e10:
  ret i64 10
}

; Gives back space s, 1 if it is not one: every mapping counted off its
; frame, its tables freed, and its slot. The host runs on the last thread's
; tables between traps, so it goes back to the boot map first, and the
; whole TLB is flushed, the ASID's entries and any walk cached through the
; tables, before a table page is written again.
define i64 @l0_host_space_free(i64 %s) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %off
off:
  call void @l0_arch_space_leave()
  %e3 = call ptr @user_entry(i64 %l1)
  %d3 = load i64, ptr %e3
  %l2 = call i64 @l0_arch_pte_pa(i64 %d3)
  %l2q = inttoptr i64 %l2 to ptr
  br label %outer
outer:
  %i = phi i64 [ 0, %off ], [ %i1, %onext ]
  %odone = icmp eq i64 %i, 512
  br i1 %odone, label %tables, label %olook
olook:
  %p2 = getelementptr i64, ptr %l2q, i64 %i
  %d2 = load i64, ptr %p2
  %has = icmp ne i64 %d2, 0
  br i1 %has, label %l3, label %onext
l3:
  %t3 = call i64 @l0_arch_pte_pa(i64 %d2)
  %t3q = inttoptr i64 %t3 to ptr
  br label %inner
inner:
  %j = phi i64 [ 0, %l3 ], [ %j1, %inext ]
  %idone = icmp eq i64 %j, 512
  br i1 %idone, label %l3done, label %ilook
ilook:
  %p3 = getelementptr i64, ptr %t3q, i64 %j
  %d = load i64, ptr %p3
  %mapped = icmp ne i64 %d, 0
  br i1 %mapped, label %count, label %inext
count:
  call void @frame_mapped(i64 %d, i32 -1)
  br label %inext
inext:
  %j1 = add i64 %j, 1
  br label %inner
l3done:
  call void @table_give(i64 %t3)
  br label %onext
onext:
  %i1 = add i64 %i, 1
  br label %outer
tables:
  call void @table_give(i64 %l2)
  call void @table_give(i64 %l1)
  %sp = getelementptr [255 x i64], ptr @sp_l1, i64 0, i64 %s
  store i64 0, ptr %sp
  ret i64 0
e1:
  ret i64 1
}

; The root table of space s, or 0 if s is not a space.
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

; The address of the leaf for the user address va in the space whose root
; table is l1, making its table of pages if make is true: 0 if the table
; is missing and not made, or no page is left to make it.
define internal i64 @l3_entry(i64 %l1, i64 %va, i1 %make) {
entry:
  %p3 = call ptr @user_entry(i64 %l1)
  %d3 = load i64, ptr %p3
  %l2 = call i64 @l0_arch_pte_pa(i64 %d3)
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
  %dt = call i64 @l0_arch_pte_table(i64 %t)
  store i64 %dt, ptr %p2
  br label %have
have:
  %d = phi i64 [ %d2, %entry ], [ %dt, %link ]
  %l3 = call i64 @l0_arch_pte_pa(i64 %d)
  %s3 = lshr i64 %va, 12
  %i3 = and i64 %s3, 511
  %o3 = shl i64 %i3, 3
  %e = add i64 %l3, %o3
  ret i64 %e
none:
  ret i64 0
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
  %d = call i64 @l0_arch_pte_page(i64 %pa, i64 %perm)
  store i64 %d, ptr %ep
  call void @frame_mapped(i64 %d, i32 1)
  %asid = add i64 %s, 1
  call void @l0_arch_mapped(i64 %asid)
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
; pages from va: device memory, read and write for the thread, never
; executable. Every page is checked before any is mapped.
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
  %qd = call i64 @l0_arch_pte_device(i64 %qa)
  store i64 %qd, ptr %qp
  %j1 = add i64 %j, 1
  br label %map
done:
  %asid = add i64 %s, 1
  call void @l0_arch_mapped(i64 %asid)
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

; The physical address of the user address va in the space whose root
; table is l1, if it is on a page space_map mapped, or 0: never a device's
; page, which only space_map_device maps.
define internal i64 @user_pa(i64 %l1, i64 %va) {
entry:
  %page = and i64 %va, -4096
  %e = call i64 @l3_entry(i64 %l1, i64 %page, i1 false)
  %none = icmp eq i64 %e, 0
  br i1 %none, label %no, label %look
look:
  %ep = inttoptr i64 %e to ptr
  %d = load i64, ptr %ep
  %unmapped = icmp eq i64 %d, 0
  br i1 %unmapped, label %no, label %which
which:
  %frame = call i64 @l0_arch_pte_pa(i64 %d)
  %k = call i64 @page_of(i64 %frame)
  %ok = icmp sge i64 %k, 0
  br i1 %ok, label %yes, label %no
yes:
  %off = and i64 %va, 4095
  %pa = add i64 %frame, %off
  ret i64 %pa
no:
  ret i64 0
}

; Whether the user address va is on a page mapped in the space whose root
; table is root, a frame's or a device's, for a CPU whose fault does not
; itself say whether anything was mapped there.
define i1 @l0_bare_user_mapped(i64 %root, i64 %va) {
entry:
  %lo = icmp uge i64 %va, 3221225472
  %hi = icmp ult i64 %va, 4294967296
  %in = and i1 %lo, %hi
  br i1 %in, label %walk, label %no
walk:
  %page = and i64 %va, -4096
  %e = call i64 @l3_entry(i64 %root, i64 %page, i1 false)
  %none = icmp eq i64 %e, 0
  br i1 %none, label %no, label %look
look:
  %ep = inttoptr i64 %e to ptr
  %d = load i64, ptr %ep
  %some = icmp ne i64 %d, 0
  ret i1 %some
no:
  ret i1 false
}

; Copies n bytes between buf and the space from va, into it when dir is 1,
; out of it when 0, after checking that every byte is on a page space_map
; mapped. An empty copy checks only that s is a space. Bytes copied in are
; made fit to run.
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
  call void @l0_arch_code_sync(i64 %pa, i64 %k)
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
; it traps; the architecture lays the words out (spec section 10.3), but on
; every one word 35 is the trap's kind, 1 an interrupt, which is taken
; before returning, its number in word 36; a spurious one sends the thread
; straight back.
define i64 @l0_host_user_run(i64 %s, ptr %words, i64 %n) {
entry:
  %l1 = call i64 @space_l1(i64 %s)
  %nos = icmp eq i64 %l1, 0
  br i1 %nos, label %e1, label %len
len:
  %right = icmp eq i64 %n, 104
  br i1 %right, label %prep, label %e7
prep:
  %asid = add i64 %s, 1
  br label %run
run:
  call void @l0_arch_user_run(ptr %words, i64 %l1, i64 %asid)
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
; Spec sections 6.14 and 10.3. The board's part drives its interrupt
; controller, which no program may open as a region, and speaks in the
; numbers section 10.3 gives each interrupt, below 1,024; this part keeps
; which are enabled and which are taken, until ended. The program runs with
; interrupts masked, so one arrives only at interrupt_wait's wait or while a
; thread runs.

@irq_taken = internal global [1024 x i8] zeroinitializer
@irq_enabled = internal global [1024 x i8] zeroinitializer
@irq_count = internal global i64 0

define i64 @l0_host_interrupt_enable(i64 %n) {
entry:
  %ok = call i1 @l0_board_irq_exists(i64 %n)
  br i1 %ok, label %on, label %out
out:
  ret i64 -3
on:
  %ep = getelementptr [1024 x i8], ptr @irq_enabled, i64 0, i64 %n
  %was = load i8, ptr %ep
  %fresh = icmp eq i8 %was, 0
  br i1 %fresh, label %count, label %done
count:
  store i8 1, ptr %ep
  %c = load i64, ptr @irq_count
  %c1 = add i64 %c, 1
  store i64 %c1, ptr @irq_count
  call void @l0_board_irq_enable(i64 %n)
  br label %done
done:
  ret i64 0
}

; Takes the interrupt the controller signals, and returns its number, or -1
; for a spurious one, which needs no end.
define internal i64 @irq_take() {
entry:
  %n = call i64 @l0_board_irq_take()
  %spurious = icmp slt i64 %n, 0
  br i1 %spurious, label %none, label %take
none:
  ret i64 -1
take:
  %tp = getelementptr [1024 x i8], ptr @irq_taken, i64 0, i64 %n
  store i8 1, ptr %tp
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
  call void @l0_arch_wait()
  %n = call i64 @irq_take()
  %spurious = icmp slt i64 %n, 0
  br i1 %spurious, label %wait, label %got
got:
  ret i64 %n
}

define i64 @l0_host_interrupt_done(i64 %n) {
entry:
  %ok = call i1 @l0_board_irq_exists(i64 %n)
  br i1 %ok, label %look, label %e8
look:
  %tp = getelementptr [1024 x i8], ptr @irq_taken, i64 0, i64 %n
  %t = load i8, ptr %tp
  %taken = icmp ne i8 %t, 0
  br i1 %taken, label %end, label %e8
end:
  store i8 0, ptr %tp
  call void @l0_board_irq_end(i64 %n)
  ret i64 0
e8:
  ret i64 8
}

; Spec section 9.2: no kernel beneath the program on a bare board.
define i64 @l0_host_supervisor(i64 %n, i64 %a, i64 %b, i64 %c) {
entry:
  ret i64 -3
}
