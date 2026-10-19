; selfwrite.ll -- a process that is not an L0 program, since no L0 program
; can write its own code: it says so on standard error, by system call 2,
; then writes over its first instruction, which its image's code segment,
; readable and executable only (spec section 10.3), does not let it. The
; L0 kernel, which maps each segment by its flags, must kill it; this
; harness, which maps its slot writable, would let it exit 0, so it runs
; only under the L0 kernel. Linked by runtime/proc.ld.

target triple = "riscv64-unknown-unknown-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".option push"
module asm ".option norvc"
module asm ".global _start"
module asm "_start:"
module asm "  li a0, 2"
module asm "  lla a1, msg"
module asm "  li a2, 32"
module asm "  li a7, 2"
module asm "  ecall"
module asm "  lla t0, _start"
module asm "  sd zero, 0(t0)"
module asm "  li a0, 0"
module asm "  li a7, 3"
module asm "  ecall"
module asm "1: j 1b"
module asm ".option pop"
module asm "msg: .ascii \22selfwrite: writing its own code\\n\22"
