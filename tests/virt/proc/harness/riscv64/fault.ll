; fault.ll -- a process that is not an L0 program, since no L0 program can
; fault: it says so on standard error, by system call 2, then reads the
; kernel's own image, which its address space maps for S-mode only. The
; kernel must kill it and go on running the others. Linked by
; runtime/proc.ld.

target triple = "riscv64-unknown-unknown-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".option push"
module asm ".option norvc"
module asm ".global _start"
module asm "_start:"
module asm "  li a0, 2"
module asm "  lla a1, msg"
module asm "  li a2, 34"
module asm "  li a7, 2"
module asm "  ecall"
module asm "  li t0, 0x80200000"
module asm "  ld a0, 0(t0)"
module asm "  li a7, 3"
module asm "  ecall"
module asm "1: j 1b"
module asm ".option pop"
module asm "msg: .ascii \22fault: reading the kernel's image\\n\22"
