; 0083's probe: at entry, whether x0 points at a device tree (its magic,
; d0 0d fe ed) and whether "driver=" is in its first 64 KB. It exits by
; semihosting with 0 if x0 is 0, 1 if it points at no device tree, 2 at one
; without the text, and 3 at one with it. Byte loads only, since the MMU is
; off. The header below is the arm64 boot protocol's (Linux's
; Documentation/arm64/booting): a branch, a text offset of 0x80000, an
; image size, flags, and the magic "ARM\x64" at byte 56.
;
; Built and booted, from the repository root:
;   clang --target=aarch64-none-elf -O1 -c roadmap/0083/probe.ll -o tmp/0083/probe.o
;   ld.lld -T runtime/virt.ld tmp/0083/probe.o -o tmp/0083/probe.elf
;   llvm-objcopy -O binary tmp/0083/probe.elf tmp/0083/probe.Image
;   qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2G -display none \
;     -monitor none -semihosting -kernel tmp/0083/probe.Image \
;     -append "driver=serial irq=33"
; which exits 3, and 2 without -append. Booted as the ELF, without the
; header's effect, it exits 0: QEMU gives a bare-metal ELF no device tree.
target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  b 2f"
module asm "  .word 0"
module asm "  .quad 0x80000"
module asm "  .quad 0x100000"
module asm "  .quad 0"
module asm "  .quad 0, 0, 0"
module asm "  .word 0x644d5241"
module asm "  .word 0"
module asm "2:"
module asm "  ldr x1, =0x4FF00000"
module asm "  mov sp, x1"
module asm "  bl probe_main"
module asm "1: b 1b"

@needle = private constant [7 x i8] c"driver="

define internal i64 @semi(i64 %op, ptr %blk) {
  %r = call i64 asm sideeffect "hlt #0xf000", "={x0},{x0},{x1},~{memory}"(i64 %op, ptr %blk)
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

define internal i8 @byte(i64 %a) {
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

define void @probe_main(i64 %dtb) noreturn {
entry:
  %zero = icmp eq i64 %dtb, 0
  br i1 %zero, label %q0, label %magic
magic:
  %b0 = call i8 @byte(i64 %dtb)
  %a1 = add i64 %dtb, 1
  %b1 = call i8 @byte(i64 %a1)
  %m0 = icmp eq i8 %b0, -48                         ; 0xd0
  %m1 = icmp eq i8 %b1, 13                          ; 0x0d
  %m = and i1 %m0, %m1
  br i1 %m, label %scan, label %q1
scan:
  %end = add i64 %dtb, 65536
  br label %loop
loop:
  %a = phi i64 [ %dtb, %scan ], [ %an, %next ]
  %over = icmp uge i64 %a, %end
  br i1 %over, label %q2, label %look
look:
  %hit = call i1 @at(i64 %a)
  br i1 %hit, label %q3, label %next
next:
  %an = add i64 %a, 1
  br label %loop
q0:
  call void @quit(i64 0)
  unreachable
q1:
  call void @quit(i64 1)
  unreachable
q2:
  call void @quit(i64 2)
  unreachable
q3:
  call void @quit(i64 3)
  unreachable
}
