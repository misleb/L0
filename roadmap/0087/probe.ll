; 0087's probe: what QEMU's riscv64 virt board, entered through OpenSBI,
; gives a raw image with the RISC-V Linux Image header, before any of
; runtime/ is written for it. It reports on semihosting's standard error,
; one line a fact, writes "uart" on the 16550, and exits by semihosting with
; status 7, so that where each goes, and where OpenSBI's banner goes, can be
; read from the outside:
;   hart, dtb, pc   a0 and a1 at entry, and where _start runs
;   len, word       the -device loader word at 0x83FFFFF8, and the first
;                   word at 0x84000000
;   args            1 if "driver=" is in the device tree's first 64 KB
;   satp            satp read back after Sv39 is turned on with every ASID
;                   bit set, so bits 44 to 59 say how many the hart has
;   tick, sip       how many counts a 100,000-count SBI timer took to raise
;                   STIP, and sip once the timer is put off to the end
;   irq             the PLIC's claim, in hart 0's S-mode context, of the
;                   16550's transmitter-empty interrupt
;
; Built and booted, from the repository root:
;   clang --target=riscv64-unknown-elf -march=rv64gc -mabi=lp64d \
;     -mcmodel=medany -mno-relax -O1 -c roadmap/0087/probe.ll -o tmp/0087/probe.o
;   ld.lld -T roadmap/0087/probe.ld --oformat binary tmp/0087/probe.o -o tmp/0087/probe.img
;   qemu-system-riscv64 -M virt,aia=none -m 1G -display none -monitor none \
;     -serial stdio -semihosting -kernel tmp/0087/probe.img \
;     -device loader,addr=0x83FFFFF8,data=5,data-len=8 -append "driver=x"
target triple = "riscv64-unknown-unknown-elf"

; The Image header (Linux's Documentation/riscv/boot-image-header.rst): a
; jump past it, a text offset of 0x200000, the image's size, flags 0
; (little-endian), version 0.2, the old magic "RISCV", and the magic
; "RSC\x05" at byte 56. Uncompressed, so the header's offsets hold.
module asm ".section .text.boot,\22ax\22"
module asm ".option push"
module asm ".option norvc"
module asm ".global _start"
module asm "_start:"
module asm "  j 2f"
module asm "  .word 0"
module asm "  .quad 0x200000"
module asm "  .quad 0x1000000"
module asm "  .quad 0"
module asm "  .word 2"
module asm "  .word 0"
module asm "  .quad 0"
module asm "  .quad 0x5643534952"
module asm "  .word 0x05435352"
module asm "  .word 0"
module asm "2:"
module asm "  auipc a2, 0"
module asm "  addi a2, a2, -64"
module asm "  li t0, 0xBC000000"
module asm "  mv sp, t0"
module asm "  la t0, probe_trap"
module asm "  csrw stvec, t0"
module asm "  li t0, 0x2000"
module asm "  csrs sstatus, t0"
module asm "  call probe_main"
module asm "1: j 1b"
module asm ".balign 4"
module asm "probe_trap:"
module asm "  csrr a0, scause"
module asm "  csrr a1, sepc"
module asm "  csrr a2, stval"
module asm "  call probe_bug"
module asm "3: j 3b"
module asm ".option pop"

; QEMU's semihosting call on RISC-V: these three uncompressed instructions,
; on one page, the operation in a0 and its block in a1.
module asm ".text"
module asm ".balign 16"
module asm "probe_semi:"
module asm ".option push"
module asm ".option norvc"
module asm "  slli zero, zero, 0x1f"
module asm "  ebreak"
module asm "  srai zero, zero, 7"
module asm ".option pop"
module asm "  ret"

declare i64 @probe_semi(i64, ptr)

@root = internal global [512 x i64] zeroinitializer, align 4096
@tt = private constant [4 x i8] c":tt\00"
@hexd = private constant [16 x i8] c"0123456789abcdef"
@needle = private constant [7 x i8] c"driver="
@s_uart = private constant [5 x i8] c"uart\0A"
@s_hart = private constant [5 x i8] c"hart "
@s_dtb = private constant [5 x i8] c"dtb  "
@s_pc = private constant [5 x i8] c"pc   "
@s_len = private constant [5 x i8] c"len  "
@s_word = private constant [5 x i8] c"word "
@s_args = private constant [5 x i8] c"args "
@s_satp = private constant [5 x i8] c"satp "
@s_tick = private constant [5 x i8] c"tick "
@s_sip = private constant [5 x i8] c"sip  "
@s_irq = private constant [5 x i8] c"irq  "
@s_bug = private constant [5 x i8] c"bug  "
@s_nl = private constant [1 x i8] c"\0A"

define internal i64 @semi(i64 %op, ptr %blk) {
entry:
  %r = call i64 @probe_semi(i64 %op, ptr %blk)
  ret i64 %r
}

define internal void @quit(i64 %st) noreturn {
entry:
  %blk = alloca [2 x i64], align 8
  store i64 131110, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  store i64 %st, ptr %p1
  %r = call i64 @semi(i64 24, ptr %blk)
  br label %hang
hang:
  br label %hang
}

@err = internal global i64 -1

define internal void @say(ptr %s, i64 %n) {
entry:
  %h0 = load i64, ptr @err
  %have = icmp sge i64 %h0, 0
  br i1 %have, label %write, label %open
open:
  %ob = alloca [3 x i64], align 8
  %tp = ptrtoint ptr @tt to i64
  store i64 %tp, ptr %ob
  %o1 = getelementptr i64, ptr %ob, i64 1
  store i64 8, ptr %o1
  %o2 = getelementptr i64, ptr %ob, i64 2
  store i64 3, ptr %o2
  %hn = call i64 @semi(i64 1, ptr %ob)
  store i64 %hn, ptr @err
  br label %write
write:
  %h = phi i64 [ %h0, %entry ], [ %hn, %open ]
  %wb = alloca [3 x i64], align 8
  store i64 %h, ptr %wb
  %w1 = getelementptr i64, ptr %wb, i64 1
  %si = ptrtoint ptr %s to i64
  store i64 %si, ptr %w1
  %w2 = getelementptr i64, ptr %wb, i64 2
  store i64 %n, ptr %w2
  %r = call i64 @semi(i64 5, ptr %wb)
  ret void
}

define internal void @hex(i64 %v) {
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
  call void @say(ptr %buf, i64 18)
  ret void
}

define internal void @line(ptr %label, i64 %v) {
entry:
  call void @say(ptr %label, i64 5)
  call void @hex(i64 %v)
  call void @say(ptr @s_nl, i64 1)
  ret void
}

; The 16550's transmit holding register at 0, its line status at 5, whose
; bit 5 says the register is empty.
define internal void @uart_put(i8 %c) {
entry:
  br label %wait
wait:
  %lsr = load volatile i8, ptr inttoptr (i64 268435461 to ptr)
  %e = and i8 %lsr, 32
  %full = icmp eq i8 %e, 0
  br i1 %full, label %wait, label %send
send:
  store volatile i8 %c, ptr inttoptr (i64 268435456 to ptr)
  ret void
}

define internal i8 @byte(i64 %a) {
entry:
  %p = inttoptr i64 %a to ptr
  %c = load volatile i8, ptr %p
  ret i8 %c
}

define internal i1 @at(i64 %a) {
entry:
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k1, %same ]
  %done = icmp eq i64 %k, 7
  br i1 %done, label %yes, label %cmp
cmp:
  %ak = add i64 %a, %k
  %c = call i8 @byte(i64 %ak)
  %np = getelementptr [7 x i8], ptr @needle, i64 0, i64 %k
  %n = load i8, ptr %np
  %eq = icmp eq i8 %c, %n
  br i1 %eq, label %same, label %no
same:
  %k1 = add i64 %k, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

define internal i64 @has_args(i64 %dtb) {
entry:
  %null = icmp eq i64 %dtb, 0
  br i1 %null, label %no, label %scan
scan:
  %end = add i64 %dtb, 65536
  br label %loop
loop:
  %a = phi i64 [ %dtb, %scan ], [ %an, %next ]
  %over = icmp uge i64 %a, %end
  br i1 %over, label %no, label %look
look:
  %hit = call i1 @at(i64 %a)
  br i1 %hit, label %yes, label %next
next:
  %an = add i64 %a, 1
  br label %loop
yes:
  ret i64 1
no:
  ret i64 0
}

define internal i64 @rdtime() {
entry:
  %t = call i64 asm sideeffect "rdtime $0", "=r"()
  ret i64 %t
}

define internal i64 @sip() {
entry:
  %v = call i64 asm sideeffect "csrr $0, sip", "=r"()
  ret i64 %v
}

; SBI's TIME extension, set_timer(stime).
define internal void @set_timer(i64 %t) {
entry:
  %r = call i64 asm sideeffect "ecall", "={x10},{x10},{x16},{x17},~{x11},~{memory}"(i64 %t, i64 0, i64 1414090053)
  ret void
}

; Waits, with sstatus.SIE clear, until sip has bit b set.
define internal void @wait_for(i64 %b) {
entry:
  br label %loop
loop:
  call void asm sideeffect "wfi", "~{memory}"()
  %v = call i64 @sip()
  %m = and i64 %v, %b
  %none = icmp eq i64 %m, 0
  br i1 %none, label %loop, label %done
done:
  ret void
}

define void @probe_bug(i64 %cause, i64 %epc, i64 %tval) noreturn {
entry:
  call void @line(ptr @s_bug, i64 %cause)
  call void @line(ptr @s_bug, i64 %epc)
  call void @line(ptr @s_bug, i64 %tval)
  call void @quit(i64 99)
  unreachable
}

define void @probe_main(i64 %hart, i64 %dtb, i64 %pc) noreturn {
entry:
  call void @uart_put(i8 117)
  call void @uart_put(i8 97)
  call void @uart_put(i8 114)
  call void @uart_put(i8 116)
  call void @uart_put(i8 10)
  call void @line(ptr @s_hart, i64 %hart)
  call void @line(ptr @s_dtb, i64 %dtb)
  call void @line(ptr @s_pc, i64 %pc)
  %len = load volatile i64, ptr inttoptr (i64 2214592504 to ptr)
  call void @line(ptr @s_len, i64 %len)
  %word = load volatile i64, ptr inttoptr (i64 2214592512 to ptr)
  call void @line(ptr @s_word, i64 %word)
  %args = call i64 @has_args(i64 %dtb)
  call void @line(ptr @s_args, i64 %args)
  ; Sv39, identity: gigapage 0 the devices, 2 the RAM, both V R W A D G,
  ; the RAM X too.
  br label %zero
zero:
  %i = phi i64 [ 0, %entry ], [ %i1, %zero ]
  %ep = getelementptr [512 x i64], ptr @root, i64 0, i64 %i
  store volatile i64 0, ptr %ep
  %i1 = add i64 %i, 1
  %zmore = icmp ult i64 %i1, 512
  br i1 %zmore, label %zero, label %fill
fill:
  store volatile i64 231, ptr @root
  %e2 = getelementptr [512 x i64], ptr @root, i64 0, i64 2
  store volatile i64 536871151, ptr %e2
  %rp = ptrtoint ptr @root to i64
  %ppn = lshr i64 %rp, 12
  %satp0 = or i64 %ppn, -8070468124433973248          ; mode 8, ASID 0xFFFF
  call void asm sideeffect "csrw satp, $0\0Asfence.vma", "r,~{memory}"(i64 %satp0)
  %satp = call i64 asm sideeffect "csrr $0, satp", "=r"()
  call void @line(ptr @s_satp, i64 %satp)
  ; The timer.
  call void @set_timer(i64 -1)
  %t0 = call i64 @rdtime()
  %due = add i64 %t0, 100000
  call void @set_timer(i64 %due)
  call void asm sideeffect "csrs sie, $0", "r"(i64 32)
  call void @wait_for(i64 32)
  %t1 = call i64 @rdtime()
  %took = sub i64 %t1, %t0
  call void @line(ptr @s_tick, i64 %took)
  call void @set_timer(i64 -1)
  call void asm sideeffect "csrc sie, $0", "r"(i64 32)
  %sv = call i64 @sip()
  call void @line(ptr @s_sip, i64 %sv)
  ; The PLIC: source 10's priority 1, enabled in context 1, threshold 0,
  ; and the 16550's transmitter-empty interrupt on.
  store volatile i32 1, ptr inttoptr (i64 201326632 to ptr)
  store volatile i32 1024, ptr inttoptr (i64 201334912 to ptr)
  store volatile i32 0, ptr inttoptr (i64 203427840 to ptr)
  store volatile i8 2, ptr inttoptr (i64 268435457 to ptr)
  call void asm sideeffect "csrs sie, $0", "r"(i64 512)
  call void @wait_for(i64 512)
  %claim = load volatile i32, ptr inttoptr (i64 203427844 to ptr)
  %cl = zext i32 %claim to i64
  call void @line(ptr @s_irq, i64 %cl)
  store volatile i8 0, ptr inttoptr (i64 268435457 to ptr)
  store volatile i32 %claim, ptr inttoptr (i64 203427844 to ptr)
  call void asm sideeffect "csrc sie, $0", "r"(i64 512)
  call void @quit(i64 7)
  unreachable
}
