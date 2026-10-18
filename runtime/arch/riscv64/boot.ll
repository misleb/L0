; boot.ll -- 64-bit RISC-V's part of a board's host: what
; runtime/bare/board.ll asks of the CPU, for any riscv64 board whose
; firmware is an SBI, as OpenSBI is. It boots the CPU in supervisor mode
; by the RISC-V Linux image protocol (spec section 10.3), takes its traps,
; runs a thread in user mode and takes its traps, writes Sv39's page
; descriptors, and drives the timer through the SBI. It names its triple,
; since most of it is assembly.
;
; The protocol: a raw image with the protocol's 64-byte header, entered in
; S-mode with the booting hart's number in a0 and the device tree's address
; in a1. The board's layout gives the stack, the bss, and the header's image
; size, and its part gives the boot map, @l0_board_boot_map, Sv39's root
; table, and the timer's frequency.
;
; A program runs in S-mode with interrupts masked, sstatus.SIE clear, and
; may run threads in U-mode in spaces of its own (spec section 6.13). A
; trap the runtime does not expect is a bug in it, and is reported on
; standard error, with the registers that say where, and stops with status
; 99.

target triple = "riscv64-unknown-unknown-elf"

; ------------------------------------------------------------------- boot

; The image header (Linux's Documentation/riscv/boot-image-header.rst): a
; jump past it, a text offset of 0x200000 from the base of RAM, the image's
; size with its bss, flags 0, little-endian, version 0.2, the old magic
; "RISCV", and the magic "RSC\x05" at byte 56; uncompressed, so that the
; offsets hold.
;
; The boot code checks that it runs where it was linked, since nothing is
; position-independent, and spins if not, with nothing yet to report on.
; It sets the stack, the trap vector, and sscratch 0, which says a trap is
; the host's own; enables floating point, which LLVM may use for copies;
; zeroes the bss; lets user mode read the time; turns on Sv39 with the
; board's boot map, ASID 0; finds how many ASID bits the hart has; and
; calls l0_bare_main with the device tree and the hart.
module asm ".section .text.boot,\22ax\22"
module asm ".option push"
module asm ".option norvc"
module asm ".global _start"
module asm "_start:"
module asm "  j l0_riscv64_boot"
module asm "  .word 0"
module asm "  .quad 0x200000"
module asm "  .quad __image_size"
module asm "  .quad 0"
module asm "  .word 2"
module asm "  .word 0"
module asm "  .quad 0"
module asm "  .quad 0x5643534952"
module asm "  .word 0x05435352"
module asm "  .word 0"
module asm "l0_riscv64_boot:"
module asm "  mv s0, a0"
module asm "  mv s1, a1"
module asm "  lla t0, _start"
module asm "  ld t1, l0_riscv64_linked"
module asm "6:"
module asm "  bne t0, t1, 6b"
module asm "  la sp, __stack_top"
module asm "  csrw sscratch, zero"
module asm "  la t0, l0_riscv64_trap"
module asm "  csrw stvec, t0"
module asm "  csrw sie, zero"
module asm "  li t0, 0x2000"
module asm "  csrs sstatus, t0"
module asm "  la t0, __bss_start"
module asm "  la t1, __bss_end"
module asm "4:"
module asm "  bgeu t0, t1, 5f"
module asm "  sd zero, 0(t0)"
module asm "  addi t0, t0, 8"
module asm "  j 4b"
module asm "5:"
module asm "  li t0, 2"
module asm "  csrs scounteren, t0"
module asm "  la t0, l0_board_boot_map"
module asm "  srli t0, t0, 12"
module asm "  li t1, 1"
module asm "  slli t1, t1, 63"
module asm "  or t0, t0, t1"
module asm "  csrw satp, t0"
module asm "  sfence.vma"
module asm "  li t1, 0xFFFF"
module asm "  slli t1, t1, 44"
module asm "  or t1, t0, t1"
module asm "  csrw satp, t1"
module asm "  csrr t1, satp"
module asm "  csrw satp, t0"
module asm "  sfence.vma"
module asm "  srli t1, t1, 44"
module asm "  li t2, 0xFFFF"
module asm "  and t1, t1, t2"
module asm "  la t2, l0_riscv64_asid_mask"
module asm "  sd t1, 0(t2)"
module asm "  mv a0, s1"
module asm "  mv a1, s0"
module asm "  call l0_bare_main"
module asm "1: j 1b"
module asm ".option pop"
module asm ".section .rodata"
module asm ".balign 8"
module asm "l0_riscv64_linked:"
module asm "  .quad _start"

; Every trap comes here, stvec in direct mode. sscratch holds 0 while the
; host runs, and the thread's context while a thread does, so swapping it
; with t6 tells the two apart. A thread's trap saves its registers into the
; words, x1 to x31 at word 1 to 31, sepc 32, the trap's kind 35, scause 36,
; stval 37, f0 to f31 from 38, fcsr 70, and returns from
; l0_riscv64_user_enter to its caller, on the host's stack. The host's own
; is reported.
module asm ".text"
module asm ".option arch, +d"
module asm ".balign 4"
module asm "l0_riscv64_trap:"
module asm "  csrrw t6, sscratch, t6"
module asm "  beqz t6, 7f"
module asm "  sd x1, 8(t6)"
module asm "  sd x2, 16(t6)"
module asm "  sd x3, 24(t6)"
module asm "  sd x4, 32(t6)"
module asm "  sd x5, 40(t6)"
module asm "  sd x6, 48(t6)"
module asm "  sd x7, 56(t6)"
module asm "  sd x8, 64(t6)"
module asm "  sd x9, 72(t6)"
module asm "  sd x10, 80(t6)"
module asm "  sd x11, 88(t6)"
module asm "  sd x12, 96(t6)"
module asm "  sd x13, 104(t6)"
module asm "  sd x14, 112(t6)"
module asm "  sd x15, 120(t6)"
module asm "  sd x16, 128(t6)"
module asm "  sd x17, 136(t6)"
module asm "  sd x18, 144(t6)"
module asm "  sd x19, 152(t6)"
module asm "  sd x20, 160(t6)"
module asm "  sd x21, 168(t6)"
module asm "  sd x22, 176(t6)"
module asm "  sd x23, 184(t6)"
module asm "  sd x24, 192(t6)"
module asm "  sd x25, 200(t6)"
module asm "  sd x26, 208(t6)"
module asm "  sd x27, 216(t6)"
module asm "  sd x28, 224(t6)"
module asm "  sd x29, 232(t6)"
module asm "  sd x30, 240(t6)"
module asm "  csrr t5, sscratch"
module asm "  sd t5, 248(t6)"
module asm "  csrw sscratch, zero"
module asm "  csrr t5, sepc"
module asm "  sd t5, 256(t6)"
module asm "  csrr t5, scause"
module asm "  srli t4, t5, 63"
module asm "  sd t4, 280(t6)"
module asm "  sd t5, 288(t6)"
module asm "  csrr t5, stval"
module asm "  sd t5, 296(t6)"
module asm "  fsd f0, 304(t6)"
module asm "  fsd f1, 312(t6)"
module asm "  fsd f2, 320(t6)"
module asm "  fsd f3, 328(t6)"
module asm "  fsd f4, 336(t6)"
module asm "  fsd f5, 344(t6)"
module asm "  fsd f6, 352(t6)"
module asm "  fsd f7, 360(t6)"
module asm "  fsd f8, 368(t6)"
module asm "  fsd f9, 376(t6)"
module asm "  fsd f10, 384(t6)"
module asm "  fsd f11, 392(t6)"
module asm "  fsd f12, 400(t6)"
module asm "  fsd f13, 408(t6)"
module asm "  fsd f14, 416(t6)"
module asm "  fsd f15, 424(t6)"
module asm "  fsd f16, 432(t6)"
module asm "  fsd f17, 440(t6)"
module asm "  fsd f18, 448(t6)"
module asm "  fsd f19, 456(t6)"
module asm "  fsd f20, 464(t6)"
module asm "  fsd f21, 472(t6)"
module asm "  fsd f22, 480(t6)"
module asm "  fsd f23, 488(t6)"
module asm "  fsd f24, 496(t6)"
module asm "  fsd f25, 504(t6)"
module asm "  fsd f26, 512(t6)"
module asm "  fsd f27, 520(t6)"
module asm "  fsd f28, 528(t6)"
module asm "  fsd f29, 536(t6)"
module asm "  fsd f30, 544(t6)"
module asm "  fsd f31, 552(t6)"
module asm "  frcsr t5"
module asm "  sd t5, 560(t6)"
module asm "  la t5, l0_riscv64_host_sp"
module asm "  ld sp, 0(t5)"
module asm "  ld ra, 0(sp)"
module asm "  ld gp, 8(sp)"
module asm "  ld tp, 16(sp)"
module asm "  ld s0, 24(sp)"
module asm "  ld s1, 32(sp)"
module asm "  ld s2, 40(sp)"
module asm "  ld s3, 48(sp)"
module asm "  ld s4, 56(sp)"
module asm "  ld s5, 64(sp)"
module asm "  ld s6, 72(sp)"
module asm "  ld s7, 80(sp)"
module asm "  ld s8, 88(sp)"
module asm "  ld s9, 96(sp)"
module asm "  ld s10, 104(sp)"
module asm "  ld s11, 112(sp)"
module asm "  fld fs0, 120(sp)"
module asm "  fld fs1, 128(sp)"
module asm "  fld fs2, 136(sp)"
module asm "  fld fs3, 144(sp)"
module asm "  fld fs4, 152(sp)"
module asm "  fld fs5, 160(sp)"
module asm "  fld fs6, 168(sp)"
module asm "  fld fs7, 176(sp)"
module asm "  fld fs8, 184(sp)"
module asm "  fld fs9, 192(sp)"
module asm "  fld fs10, 200(sp)"
module asm "  fld fs11, 208(sp)"
module asm "  addi sp, sp, 224"
module asm "  ret"
module asm "7:"
module asm "  csrrw t6, sscratch, t6"
module asm "  csrr a0, scause"
module asm "  csrr a1, sepc"
module asm "  csrr a2, stval"
module asm "  call l0_riscv64_bug"
module asm "8: j 8b"

; l0_riscv64_user_enter(words, satp, flush): saves what its caller expects
; kept (ra, gp, tp, s0 to s11, fs0 to fs11) on this stack, records the
; stack, switches to the thread's space, flushing the TLB first when flush
; is not 0, loads its registers from the words, sets sscratch to them, and
; srets to U-mode with interrupts on there.
module asm ".global l0_riscv64_user_enter"
module asm "l0_riscv64_user_enter:"
module asm "  addi sp, sp, -224"
module asm "  sd ra, 0(sp)"
module asm "  sd gp, 8(sp)"
module asm "  sd tp, 16(sp)"
module asm "  sd s0, 24(sp)"
module asm "  sd s1, 32(sp)"
module asm "  sd s2, 40(sp)"
module asm "  sd s3, 48(sp)"
module asm "  sd s4, 56(sp)"
module asm "  sd s5, 64(sp)"
module asm "  sd s6, 72(sp)"
module asm "  sd s7, 80(sp)"
module asm "  sd s8, 88(sp)"
module asm "  sd s9, 96(sp)"
module asm "  sd s10, 104(sp)"
module asm "  sd s11, 112(sp)"
module asm "  fsd fs0, 120(sp)"
module asm "  fsd fs1, 128(sp)"
module asm "  fsd fs2, 136(sp)"
module asm "  fsd fs3, 144(sp)"
module asm "  fsd fs4, 152(sp)"
module asm "  fsd fs5, 160(sp)"
module asm "  fsd fs6, 168(sp)"
module asm "  fsd fs7, 176(sp)"
module asm "  fsd fs8, 184(sp)"
module asm "  fsd fs9, 192(sp)"
module asm "  fsd fs10, 200(sp)"
module asm "  fsd fs11, 208(sp)"
module asm "  la t0, l0_riscv64_host_sp"
module asm "  sd sp, 0(t0)"
module asm "  csrw satp, a1"
module asm "  beqz a2, 9f"
module asm "  sfence.vma"
module asm "9:"
module asm "  ld t0, 256(a0)"
module asm "  csrw sepc, t0"
module asm "  li t0, 0x100"
module asm "  csrc sstatus, t0"
module asm "  li t0, 0x20"
module asm "  csrs sstatus, t0"
module asm "  ld t0, 560(a0)"
module asm "  fscsr t0"
module asm "  fld f0, 304(a0)"
module asm "  fld f1, 312(a0)"
module asm "  fld f2, 320(a0)"
module asm "  fld f3, 328(a0)"
module asm "  fld f4, 336(a0)"
module asm "  fld f5, 344(a0)"
module asm "  fld f6, 352(a0)"
module asm "  fld f7, 360(a0)"
module asm "  fld f8, 368(a0)"
module asm "  fld f9, 376(a0)"
module asm "  fld f10, 384(a0)"
module asm "  fld f11, 392(a0)"
module asm "  fld f12, 400(a0)"
module asm "  fld f13, 408(a0)"
module asm "  fld f14, 416(a0)"
module asm "  fld f15, 424(a0)"
module asm "  fld f16, 432(a0)"
module asm "  fld f17, 440(a0)"
module asm "  fld f18, 448(a0)"
module asm "  fld f19, 456(a0)"
module asm "  fld f20, 464(a0)"
module asm "  fld f21, 472(a0)"
module asm "  fld f22, 480(a0)"
module asm "  fld f23, 488(a0)"
module asm "  fld f24, 496(a0)"
module asm "  fld f25, 504(a0)"
module asm "  fld f26, 512(a0)"
module asm "  fld f27, 520(a0)"
module asm "  fld f28, 528(a0)"
module asm "  fld f29, 536(a0)"
module asm "  fld f30, 544(a0)"
module asm "  fld f31, 552(a0)"
module asm "  csrw sscratch, a0"
module asm "  ld x1, 8(a0)"
module asm "  ld x2, 16(a0)"
module asm "  ld x3, 24(a0)"
module asm "  ld x4, 32(a0)"
module asm "  ld x5, 40(a0)"
module asm "  ld x6, 48(a0)"
module asm "  ld x7, 56(a0)"
module asm "  ld x8, 64(a0)"
module asm "  ld x9, 72(a0)"
module asm "  ld x11, 88(a0)"
module asm "  ld x12, 96(a0)"
module asm "  ld x13, 104(a0)"
module asm "  ld x14, 112(a0)"
module asm "  ld x15, 120(a0)"
module asm "  ld x16, 128(a0)"
module asm "  ld x17, 136(a0)"
module asm "  ld x18, 144(a0)"
module asm "  ld x19, 152(a0)"
module asm "  ld x20, 160(a0)"
module asm "  ld x21, 168(a0)"
module asm "  ld x22, 176(a0)"
module asm "  ld x23, 184(a0)"
module asm "  ld x24, 192(a0)"
module asm "  ld x25, 200(a0)"
module asm "  ld x26, 208(a0)"
module asm "  ld x27, 216(a0)"
module asm "  ld x28, 224(a0)"
module asm "  ld x29, 232(a0)"
module asm "  ld x30, 240(a0)"
module asm "  ld x31, 248(a0)"
module asm "  ld x10, 80(a0)"
module asm "  sret"

; QEMU's semihosting call on RISC-V: these three uncompressed instructions,
; on one page, the operation in a0 and its block in a1.
module asm ".balign 16"
module asm "l0_riscv64_semi:"
module asm ".option push"
module asm ".option norvc"
module asm "  slli zero, zero, 0x1f"
module asm "  ebreak"
module asm "  srai zero, zero, 7"
module asm ".option pop"
module asm "  ret"

@l0_board_boot_map = external global i8

; Defined by runtime/bare/board.ll.
declare void @l0_bare_main(i64, i64) noreturn
declare void @l0_bare_put_hex(i64)
declare i1 @l0_bare_user_mapped(i64, i64)
declare i64 @l0_host_write(i64, ptr, i64)
declare void @l0_host_exit(i64) noreturn

; Defined by the board's part.
declare i64 @l0_board_timebase_hz()

declare void @l0_riscv64_user_enter(ptr, i64, i64)
declare i64 @l0_riscv64_semi(i64, ptr)

; Read and written by the boot code and l0_riscv64_user_enter's trap path.
@l0_riscv64_host_sp = global i64 0
@l0_riscv64_asid_mask = global i64 0

@m_trap = private constant [32 x i8] c"l0: machine exception: scause = "
@m_epc = private constant [9 x i8] c", sepc = "
@m_tval = private constant [10 x i8] c", stval = "
@m_nl = private constant [1 x i8] c"\0A"

define void @l0_riscv64_bug(i64 %cause, i64 %epc, i64 %tval) noreturn {
entry:
  %a = call i64 @l0_host_write(i64 2, ptr @m_trap, i64 32)
  call void @l0_bare_put_hex(i64 %cause)
  %b = call i64 @l0_host_write(i64 2, ptr @m_epc, i64 9)
  call void @l0_bare_put_hex(i64 %epc)
  %c = call i64 @l0_host_write(i64 2, ptr @m_tval, i64 10)
  call void @l0_bare_put_hex(i64 %tval)
  %d = call i64 @l0_host_write(i64 2, ptr @m_nl, i64 1)
  call void @l0_host_exit(i64 99)
  unreachable
}

; Spec section 6.16: riscv64 is CPU 2.
define i64 @l0_host_machine() {
entry:
  ret i64 2
}

; ----------------------------------------------- semihosting, the barrier

define i64 @l0_arch_semihost(i64 %op, ptr %blk) {
entry:
  %r = call i64 @l0_riscv64_semi(i64 %op, ptr %blk)
  ret i64 %r
}

define void @l0_arch_barrier() {
entry:
  call void asm sideeffect "fence iorw, iorw", "~{memory}"()
  ret void
}

; Waits for an interrupt, with them masked, as the program runs: wfi wakes
; for any enabled in sie, whatever sstatus.SIE says.
define void @l0_arch_wait() {
entry:
  call void asm sideeffect "fence iorw, iorw\0Awfi", "~{memory}"()
  ret void
}

; ------------------------------------------------- the counter and timer

; The time CSR, at the board's timebase counts a second.
define i64 @l0_arch_counter() {
entry:
  %t = call i64 asm sideeffect "rdtime $0", "=r"()
  ret i64 %t
}

define i64 @l0_arch_counter_hz() {
entry:
  %hz = call i64 @l0_board_timebase_hz()
  ret i64 %hz
}

; SBI's TIME extension, set_timer(stime), which raises the supervisor
; timer interrupt once the time reaches stime, and clears it till then; the
; SBI works with or without the Sstc extension, which the U74 lacks.
define void @l0_arch_timer_set(i64 %t) {
entry:
  %r = call i64 asm sideeffect "ecall", "={x10},{x10},{x16},{x17},~{x11},~{memory}"(i64 %t, i64 0, i64 1414090053)
  ret void
}

define void @l0_arch_timer_off() {
entry:
  call void @l0_arch_timer_set(i64 -1)
  ret void
}

; Whether the supervisor timer's interrupt is pending, sip.STIP.
define i1 @l0_riscv64_timer_pending() {
entry:
  %sip = call i64 asm sideeffect "csrr $0, sip", "=r"()
  %b = and i64 %sip, 32
  %p = icmp ne i64 %b, 0
  ret i1 %p
}

; The interrupts sie lets reach the hart: bit 5 the timer's, bit 9 the
; external controller's.
define void @l0_riscv64_sie_on(i64 %bits) {
entry:
  call void asm sideeffect "csrs sie, $0", "r"(i64 %bits)
  ret void
}

define void @l0_riscv64_sie_off(i64 %bits) {
entry:
  call void asm sideeffect "csrc sie, $0", "r"(i64 %bits)
  ret void
}

; --------------------------------------------------------------- user mode
;
; Spec sections 6.13 and 10.3. Sv39: a descriptor holds a page's number
; from bit 10, and V, R, W, X, U, G, A, D in bits 0 to 7. Every user leaf is
; a 4 KB page with U set, not global, so tagged with the space's ASID, in
; satp's bits 44 up, when the hart has enough of them: with fewer than 8
; bits every space runs with ASID 0, and moving to a space flushes the TLB.
; Leaves always set A, and D when they may be written, since a hart need
; not set them itself; tables set V alone. Device memory and normal memory
; differ by where they are, by the board's physical memory attributes, so
; their leaves differ only in their bits for the thread.

define i64 @l0_arch_pte_table(i64 %pa) {
entry:
  %ppn = lshr i64 %pa, 12
  %f = shl i64 %ppn, 10
  %d = or i64 %f, 1
  ret i64 %d
}

define i64 @l0_arch_pte_pa(i64 %d) {
entry:
  %ppn0 = lshr i64 %d, 10
  %ppn = and i64 %ppn0, 17592186044415                     ; 44 bits
  %pa = shl i64 %ppn, 12
  ret i64 %pa
}

; A user page for the frame at pa and perm, spec section 6.13: V, R, U, A,
; and W and D if perm has bit 0, X if it has bit 1.
define i64 @l0_arch_pte_page(i64 %pa, i64 %perm) {
entry:
  %w = and i64 %perm, 1
  %x = and i64 %perm, 2
  %rw = icmp ne i64 %w, 0
  %wb = select i1 %rw, i64 132, i64 0                       ; W, D
  %ex = icmp ne i64 %x, 0
  %xb = select i1 %ex, i64 8, i64 0                         ; X
  %b0 = or i64 %wb, %xb
  %bits = or i64 %b0, 83                                    ; V, R, U, A
  %f = call i64 @l0_arch_pte_table(i64 %pa)
  %frame = xor i64 %f, 1
  %d = or i64 %frame, %bits
  ret i64 %d
}

; A device's page at pa: V, R, W, U, A, D, never executable.
define i64 @l0_arch_pte_device(i64 %pa) {
entry:
  %f = call i64 @l0_arch_pte_table(i64 %pa)
  %frame = xor i64 %f, 1
  %d = or i64 %frame, 215
  ret i64 %d
}

define internal i1 @asids() {
entry:
  %m = load i64, ptr @l0_riscv64_asid_mask
  %ok = icmp uge i64 %m, 255
  ret i1 %ok
}

define void @l0_arch_tables_written() {
entry:
  call void asm sideeffect "fence rw, rw", "~{memory}"()
  ret void
}

; Pages just mapped in the space with this ASID: a hart may cache that an
; entry was invalid, so its ASID's entries are flushed.
define void @l0_arch_mapped(i64 %asid) {
entry:
  %ok = call i1 @asids()
  br i1 %ok, label %one, label %all
one:
  call void asm sideeffect "sfence.vma zero, $0", "r,~{memory}"(i64 %asid)
  ret void
all:
  call void asm sideeffect "sfence.vma", "~{memory}"()
  ret void
}

define void @l0_arch_tlb_page(i64 %asid, i64 %va) {
entry:
  %ok = call i1 @asids()
  br i1 %ok, label %one, label %all
one:
  call void asm sideeffect "sfence.vma $0, $1", "r,r,~{memory}"(i64 %va, i64 %asid)
  ret void
all:
  call void asm sideeffect "sfence.vma $0, zero", "r,~{memory}"(i64 %va)
  ret void
}

; Back on the boot map, ASID 0, with the whole TLB flushed, before a
; space's tables are given back.
define void @l0_arch_space_leave() {
entry:
  %boot = ptrtoint ptr @l0_board_boot_map to i64
  %satp = call i64 @satp_of(i64 %boot, i64 0)
  call void asm sideeffect "csrw satp, $0\0Asfence.vma", "r,~{memory}"(i64 %satp)
  ret void
}

; Bytes copied into a space are fetched as instructions after fence.i, on
; the one hart that runs the program and its threads.
define void @l0_arch_code_sync(i64 %pa, i64 %n) {
entry:
  call void asm sideeffect "fence.i", "~{memory}"()
  ret void
}

define internal i64 @satp_of(i64 %root, i64 %asid) {
entry:
  %ppn = lshr i64 %root, 12
  %as = shl i64 %asid, 44
  %a = or i64 %ppn, %as
  %s = or i64 %a, -9223372036854775808                      ; mode 8, Sv39
  ret i64 %s
}

; Whether va, a fault's address, is on a page the space whose root table is
; root maps, the host's own or the thread's: a fault there is the page's
; permissions, and anywhere else, nothing mapped, as on arm64.
define internal i1 @mapped_at(i64 %root, i64 %va) {
entry:
  %hi = lshr i64 %va, 39
  %low = icmp eq i64 %hi, 0
  br i1 %low, label %look, label %no
look:
  %i0 = lshr i64 %va, 30
  %i = and i64 %i0, 511
  %rp = inttoptr i64 %root to ptr
  %ep = getelementptr i64, ptr %rp, i64 %i
  %e = load i64, ptr %ep
  %none = icmp eq i64 %e, 0
  br i1 %none, label %no, label %kind
kind:
  %rwx = and i64 %e, 14
  %leaf = icmp ne i64 %rwx, 0
  br i1 %leaf, label %yes, label %walk
walk:
  %m = call i1 @l0_bare_user_mapped(i64 %root, i64 %va)
  ret i1 %m
yes:
  ret i1 true
no:
  ret i1 false
}

; Runs the thread whose context is the 104 words at words, in the space
; whose root table is root, until it traps; then, for a system call, word
; 32 is past the ecall, and for a page fault, an instruction, load, or
; store page fault, word 34 is 1 if nothing is mapped at its address.
define void @l0_arch_user_run(ptr %words, i64 %root, i64 %asid) {
entry:
  %ok = call i1 @asids()
  %as = select i1 %ok, i64 %asid, i64 0
  %flush = select i1 %ok, i64 0, i64 1
  %satp = call i64 @satp_of(i64 %root, i64 %as)
  %w33 = getelementptr i64, ptr %words, i64 33
  store i64 0, ptr %w33
  %w34 = getelementptr i64, ptr %words, i64 34
  store i64 0, ptr %w34
  call void @l0_riscv64_user_enter(ptr %words, i64 %satp, i64 %flush)
  %kp = getelementptr i64, ptr %words, i64 35
  %kind = load i64, ptr %kp
  %exc = icmp eq i64 %kind, 0
  br i1 %exc, label %cause, label %done
cause:
  %cp = getelementptr i64, ptr %words, i64 36
  %c = load i64, ptr %cp
  %call = icmp eq i64 %c, 8
  br i1 %call, label %past, label %fault
past:
  %pp = getelementptr i64, ptr %words, i64 32
  %pc = load i64, ptr %pp
  %pc4 = add i64 %pc, 4
  store i64 %pc4, ptr %pp
  br label %done
fault:
  %f12 = icmp eq i64 %c, 12
  %f13 = icmp eq i64 %c, 13
  %f15 = icmp eq i64 %c, 15
  %f0 = or i1 %f12, %f13
  %pf = or i1 %f0, %f15
  br i1 %pf, label %page, label %done
page:
  %vp = getelementptr i64, ptr %words, i64 37
  %va = load i64, ptr %vp
  %m = call i1 @mapped_at(i64 %root, i64 %va)
  %miss = select i1 %m, i64 0, i64 1
  store i64 %miss, ptr %w34
  br label %done
done:
  ret void
}
