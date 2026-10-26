; gicv2.ll -- Arm's GICv2 interrupt controller, for a board's part: its
; distributor at d and its CPU interface at c, wherever the board puts
; them, by volatile 32- and 8-bit accesses, which device memory keeps in
; order. It carries no triple. QEMU's arm virt board has one, and the
; Raspberry Pi 4's GIC-400 is one.
;
; The CPU interface runs with EOImode 1: taking an interrupt reads its
; acknowledge register and at once writes its end-of-interrupt register,
; which drops the running priority so that others can come, and
; deactivating it, later, lets the same one come again. That is spec section
; 6.14's taken until ended. Every interrupt has priority 0, the highest,
; and goes to CPU 0.
;
; SGIs are the host's own, sent by one CPU to wake another that sleeps
; (spec section 10.3): SGI 0 is enabled on each CPU interface as it is set
; up, and one that is signalled is ended at once, as it is taken, and given
; as spurious.

declare void @l0_arch_barrier()

define internal void @w32(i64 %a, i32 %v) {
entry:
  %p = inttoptr i64 %a to ptr
  store volatile i32 %v, ptr %p
  ret void
}

define internal void @w8(i64 %a, i8 %v) {
entry:
  %p = inttoptr i64 %a to ptr
  store volatile i8 %v, ptr %p
  ret void
}

define internal i32 @r32(i64 %a) {
entry:
  %p = inttoptr i64 %a to ptr
  %v = load volatile i32, ptr %p
  ret i32 %v
}

; The distributor on, the CPU interface's priority mask letting every
; priority through, the CPU interface on, with EOImode 1, and its SGI 0.
define void @l0_gicv2_init(i64 %d, i64 %c) {
entry:
  call void @w32(i64 %d, i32 1)                             ; GICD_CTLR
  %pmr = add i64 %c, 4
  call void @w32(i64 %pmr, i32 240)                         ; GICC_PMR
  call void @w32(i64 %c, i32 513)                           ; GICC_CTLR
  %en = add i64 %d, 256                                     ; GICD_ISENABLER0
  call void @w32(i64 %en, i32 1)
  ret void
}

; The calling CPU's interface, as a target list's bit: what its banked
; GICD_ITARGETSR0 reads for SGI 0.
define i64 @l0_gicv2_self(i64 %d) {
entry:
  %ta = add i64 %d, 2048                                    ; GICD_ITARGETSR0
  %p = inttoptr i64 %ta to ptr
  %t = load volatile i8, ptr %p
  %t64 = zext i8 %t to i64
  ret i64 %t64
}

; SGI 0 sent to the CPU interfaces of the target list t, once every store
; before it is seen.
define void @l0_gicv2_wake(i64 %d, i64 %t) {
entry:
  call void @l0_arch_barrier()
  %sa = add i64 %d, 3840                                    ; GICD_SGIR
  %l = and i64 %t, 255
  %v = shl i64 %l, 16
  %v32 = trunc i64 %v to i32
  call void @w32(i64 %sa, i32 %v32)
  ret void
}

; Interrupt id on, and, for a shared one, from 32, sent to CPU 0.
define void @l0_gicv2_enable(i64 %d, i64 %id) {
entry:
  %spi = icmp uge i64 %id, 32
  br i1 %spi, label %target, label %enable
target:
  %t0 = add i64 %d, 2048                                    ; GICD_ITARGETSR
  %ta = add i64 %t0, %id
  call void @w8(i64 %ta, i8 1)
  br label %enable
enable:
  %word = lshr i64 %id, 5
  %wo = shl i64 %word, 2
  %r0 = add i64 %d, 256                                     ; GICD_ISENABLER
  %ra = add i64 %r0, %wo
  %bit = and i64 %id, 31
  %m = shl i64 1, %bit
  %m32 = trunc i64 %m to i32
  call void @w32(i64 %ra, i32 %m32)
  call void @l0_arch_barrier()
  ret void
}

; Shared interrupt id edge-triggered, its field's upper bit set in
; GICD_ICFGR, which holds 16 two-bit fields a word; a board calls this
; before enabling it, since the architecture leaves a change to an enabled
; one unpredictable. Every other stays as it resets, level.
define void @l0_gicv2_edge(i64 %d, i64 %id) {
entry:
  %word = lshr i64 %id, 4
  %wo = shl i64 %word, 2
  %r0 = add i64 %d, 3072                                    ; GICD_ICFGR
  %ra = add i64 %r0, %wo
  %field = and i64 %id, 15
  %b0 = shl i64 %field, 1
  %bit = add i64 %b0, 1
  %m = shl i64 1, %bit
  %m32 = trunc i64 %m to i32
  %old = call i32 @r32(i64 %ra)
  %new = or i32 %old, %m32
  call void @w32(i64 %ra, i32 %new)
  ret void
}

; The id of the interrupt the CPU interface signals, its priority dropped,
; or -1 for a spurious one, from 1,020, which needs no end, or for an SGI,
; below 16, which is ended here, with the sender's number its IAR holds.
define i64 @l0_gicv2_take(i64 %c) {
entry:
  %ia = add i64 %c, 12                                      ; GICC_IAR
  %iar = call i32 @r32(i64 %ia)
  %id32 = and i32 %iar, 1023
  %id = zext i32 %id32 to i64
  %spurious = icmp uge i64 %id, 1020
  br i1 %spurious, label %none, label %take
none:
  ret i64 -1
take:
  %ea = add i64 %c, 16                                      ; GICC_EOIR
  call void @w32(i64 %ea, i32 %iar)
  %sgi = icmp ult i64 %id, 16
  br i1 %sgi, label %host, label %give
host:
  %da = add i64 %c, 4096                                    ; GICC_DIR
  call void @w32(i64 %da, i32 %iar)
  ret i64 -1
give:
  ret i64 %id
}

; Deactivates interrupt id, so that it can come again.
define void @l0_gicv2_end(i64 %c, i64 %id) {
entry:
  %da = add i64 %c, 4096                                    ; GICC_DIR
  %id32 = trunc i64 %id to i32
  call void @w32(i64 %da, i32 %id32)
  ret void
}
