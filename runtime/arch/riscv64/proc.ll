; proc.ll -- 64-bit RISC-V's part of the host for a process of a kernel:
; what runtime/bare/proc.ll asks of the CPU, in U-mode. It names its triple,
; since its entry and its system calls are RISC-V instructions, and no board.
;
; A system call is ecall, the number in a7, arguments in a0 to a3, the
; result in a0 (spec section 10.3). The time CSR, which the kernel lets
; U-mode read, counts at the board's timebase, which a process cannot
; learn, so the clock is a system call, 11, which the kernel answers. The
; barrier is fence iorw, iorw.

target triple = "riscv64-unknown-unknown-elf"

module asm ".section .text.boot,\22ax\22"
module asm ".global _start"
module asm "_start:"
module asm "  call l0_proc_main"
module asm "1: j 1b"

declare void @l0_proc_main() noreturn

define i64 @l0_arch_syscall(i64 %nr, i64 %a, i64 %b, i64 %c, i64 %d) {
entry:
  %r = call i64 asm sideeffect "ecall", "={x10},{x10},{x11},{x12},{x13},{x17},~{memory}"(i64 %a, i64 %b, i64 %c, i64 %d, i64 %nr)
  ret i64 %r
}

; Call 11, the clock, as l0_host_clock_ns gives it.
define i64 @l0_host_clock_ns() {
entry:
  %r = call i64 @l0_arch_syscall(i64 11, i64 0, i64 0, i64 0, i64 0)
  ret i64 %r
}

; Spec section 6.16: riscv64 is CPU 2.
define i64 @l0_host_machine() {
entry:
  ret i64 2
}

define void @l0_host_barrier() {
entry:
  call void asm sideeffect "fence iorw, iorw", "~{memory}"()
  ret void
}
