; selfwrite.ll -- a process that is not an L0 program, since no L0 program
; can write its own code: it says so on standard error, by system call 2,
; then writes over its first instruction, which its image's code segment,
; readable and executable only (spec section 10.3), does not let it. The
; L0 kernel, which maps each segment by its flags, must kill it; this
; harness, which maps its slot writable, would let it exit 0, so it runs
; only under the L0 kernel. Linked by runtime/proc.ld.

target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  mov x0, #2"
module asm "  adr x1, msg"
module asm "  mov x2, #32"
module asm "  mov x8, #2"
module asm "  svc #0"
module asm "  adr x9, _start"
module asm "  str xzr, [x9]"
module asm "  mov x0, #0"
module asm "  mov x8, #3"
module asm "  svc #0"
module asm "1: b 1b"
module asm "msg: .ascii \22selfwrite: writing its own code\\n\22"
