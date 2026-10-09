; fault.ll -- a process that is not an L0 program, since no L0 program can
; fault: it says so on standard error, then reads the kernel's own image,
; which its address space maps for EL1 only. The kernel must report it and
; go on running the others.

target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  mov x0, #2"
module asm "  adr x1, msg"
module asm "  mov x2, #34"
module asm "  mov x8, #2"
module asm "  svc #0"
module asm "  ldr x9, =0x40080000"
module asm "  ldr x0, [x9]"
module asm "  mov x8, #3"
module asm "  svc #0"
module asm "1: b 1b"
module asm "msg: .ascii \22fault: reading the kernel's image\\n\22"
