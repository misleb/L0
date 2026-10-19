; bigbss.ll -- a process whose bss is 6 MB, more than the 4 MB that a
; process's image was capped at before its image was an ELF (spec section
; 10.3): it reads its bss's first, middle, and last bytes, which must be 0,
; writes 7 to the last and reads it back, and exits with it, or with 1 if a
; byte was not 0. Its image is over this harness's 4 MB slot, so it runs
; only under the L0 kernel. Linked by runtime/proc.ld.

target triple = "aarch64-unknown-none-elf"

@big = global [6291456 x i8] zeroinitializer

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  bl check"
module asm "  mov x8, #3"
module asm "  svc #0"
module asm "1: b 1b"

define i64 @check() {
  %mid = getelementptr [6291456 x i8], ptr @big, i64 0, i64 3145728
  %last = getelementptr [6291456 x i8], ptr @big, i64 0, i64 6291455
  %a = load volatile i8, ptr @big
  %b = load volatile i8, ptr %mid
  %c = load volatile i8, ptr %last
  store volatile i8 7, ptr %last
  %d = load volatile i8, ptr %last
  %ab = or i8 %a, %b
  %abc = or i8 %ab, %c
  %zero = icmp eq i8 %abc, 0
  %dw = zext i8 %d to i64
  %r = select i1 %zero, i64 %dw, i64 1
  ret i64 %r
}
