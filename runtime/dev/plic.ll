; plic.ll -- the RISC-V platform-level interrupt controller, for a board's
; part: its registers at b, wherever the board puts it, and the context
; that is the booting hart's supervisor mode, which the board says. It
; carries no triple. QEMU's riscv64 virt board has one, and so does the
; VisionFive 2.
;
; Every source enabled gets priority 1, and the context's threshold is 0,
; so all of them reach it, the lowest number first when several are
; pending. Claiming a source takes it, and completing it lets it come
; again: spec section 6.14's taken until ended, with nothing more.

declare void @l0_arch_barrier()

; The context's threshold: every priority above 0.
define void @l0_plic_init(i64 %b, i64 %ctx) {
entry:
  %t0 = add i64 %b, 2097152                                 ; 0x200000
  %to = shl i64 %ctx, 12
  %ta = add i64 %t0, %to
  %tp = inttoptr i64 %ta to ptr
  store volatile i32 0, ptr %tp
  ret void
}

; Source id on, priority 1, enabled for the context.
define void @l0_plic_enable(i64 %b, i64 %ctx, i64 %id) {
entry:
  %po = shl i64 %id, 2
  %pa = add i64 %b, %po
  %pp = inttoptr i64 %pa to ptr
  store volatile i32 1, ptr %pp
  %e0 = add i64 %b, 8192                                    ; 0x2000
  %eo = shl i64 %ctx, 7
  %e1 = add i64 %e0, %eo
  %word = lshr i64 %id, 5
  %wo = shl i64 %word, 2
  %ea = add i64 %e1, %wo
  %ep = inttoptr i64 %ea to ptr
  %old = load volatile i32, ptr %ep
  %bit = and i64 %id, 31
  %m = shl i64 1, %bit
  %m32 = trunc i64 %m to i32
  %new = or i32 %old, %m32
  store volatile i32 %new, ptr %ep
  call void @l0_arch_barrier()
  ret void
}

define internal i64 @claim_addr(i64 %b, i64 %ctx) {
entry:
  %t0 = add i64 %b, 2097156                                 ; 0x200004
  %to = shl i64 %ctx, 12
  %ca = add i64 %t0, %to
  ret i64 %ca
}

; The source the context claims, taken, or -1 when none is pending.
define i64 @l0_plic_claim(i64 %b, i64 %ctx) {
entry:
  %ca = call i64 @claim_addr(i64 %b, i64 %ctx)
  %cp = inttoptr i64 %ca to ptr
  %id32 = load volatile i32, ptr %cp
  %id = zext i32 %id32 to i64
  %none = icmp eq i64 %id, 0
  %r = select i1 %none, i64 -1, i64 %id
  ret i64 %r
}

; Completes source id, so that it can come again.
define void @l0_plic_complete(i64 %b, i64 %ctx, i64 %id) {
entry:
  %ca = call i64 @claim_addr(i64 %b, i64 %ctx)
  %cp = inttoptr i64 %ca to ptr
  %id32 = trunc i64 %id to i32
  store volatile i32 %id32, ptr %cp
  ret void
}
