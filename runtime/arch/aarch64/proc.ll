; proc.ll -- arm64's part of the host for a process of a kernel: what
; runtime/bare/proc.ll asks of the CPU, at EL0 of an arm64 machine. It names
; its triple, since its entry and its system calls are arm64 instructions,
; and no board.
;
; A system call is svc #0, the number in x8, arguments in x0 to x3, the
; result in x0 (spec section 10.3). The clock is the virtual counter, which
; the kernel lets EL0 read, and the barrier is dsb sy.

target triple = "aarch64-unknown-none-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  bl l0_proc_main"
module asm "1: b 1b"

declare void @l0_proc_main() noreturn

define i64 @l0_arch_syscall(i64 %nr, i64 %a, i64 %b, i64 %c, i64 %d) {
entry:
  %r = call i64 asm sideeffect "svc #0", "={x0},{x0},{x1},{x2},{x3},{x8},~{memory}"(i64 %a, i64 %b, i64 %c, i64 %d, i64 %nr)
  ret i64 %r
}

; The virtual counter, at cntfrq_el0 counts a second, in seconds and then
; nanoseconds, so that the product cannot overflow; the kernel lets EL0
; read both.
define i64 @l0_host_clock_ns() {
entry:
  %cnt = call i64 asm sideeffect "isb\0Amrs $0, cntvct_el0", "=r"()
  %frq = call i64 asm "mrs $0, cntfrq_el0", "=r"()
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

; Spec section 6.16: aarch64 is CPU 1.
define i64 @l0_host_machine() {
entry:
  ret i64 1
}

define void @l0_host_barrier() {
entry:
  call void asm sideeffect "dsb sy", "~{memory}"()
  ret void
}
