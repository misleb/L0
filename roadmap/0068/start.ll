; Smallest bare-metal image for QEMU's aarch64 virt board: set up a stack,
; allow FP and SIMD, write "hi" to the PL011 at 0x09000000, then stop with
; status 3 through semihosting's SYS_EXIT, so the host can read the status.
; The first prototype, linked alone by link.ld; metal.ll grew from it.

target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  mov x0, #(3 << 20)"
module asm "  msr cpacr_el1, x0"
module asm "  isb"
module asm "  ldr x0, =__stack_top"
module asm "  mov sp, x0"
module asm "  bl boot_main"
module asm "1: b 1b"

define void @putc(i8 %c) {
  store volatile i8 %c, ptr inttoptr (i64 150994944 to ptr)
  ret void
}

define void @exit(i64 %status) noreturn {
  %blk = alloca [2 x i64], align 8
  store i64 131110, ptr %blk
  %p1 = getelementptr i64, ptr %blk, i64 1
  store i64 %status, ptr %p1
  call void asm sideeffect "mov x0, #0x18\0Amov x1, $0\0Ahlt #0xf000", "r,~{x0},~{x1},~{memory}"(ptr %blk)
  unreachable
}

define void @boot_main() {
  call void @putc(i8 104)
  call void @putc(i8 105)
  call void @putc(i8 10)
  call void @exit(i64 3)
  unreachable
}
