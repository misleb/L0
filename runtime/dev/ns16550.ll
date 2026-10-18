; ns16550.ll -- the 16550 serial port, for a board's part: its registers at
; base, each 1 << shift bytes from the last, wherever the board puts it. It
; carries no triple. QEMU's riscv64 virt board has one, its registers a byte
; apart, and the VisionFive 2's DesignWare UART is one, its registers 4
; bytes apart.

; Writes c, once the transmit holding register is empty: the line status
; register, the 5th, has bit 5 set when it is.
define void @l0_ns16550_put(i64 %base, i64 %shift, i8 %c) {
entry:
  %lo = shl i64 5, %shift
  %la = add i64 %base, %lo
  %lp = inttoptr i64 %la to ptr
  br label %wait
wait:
  %lsr = load volatile i8, ptr %lp
  %e = and i8 %lsr, 32
  %full = icmp eq i8 %e, 0
  br i1 %full, label %wait, label %send
send:
  %dp = inttoptr i64 %base to ptr
  store volatile i8 %c, ptr %dp
  ret void
}
