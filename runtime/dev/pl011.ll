; pl011.ll -- Arm's PL011 serial port, for a board's part: its registers at
; base, wherever the board puts it. It carries no triple. QEMU's arm virt
; board has one, and so does the Raspberry Pi 4.

; Writes c, once the transmit FIFO has room: the flag register, at 0x18,
; has bit 5 set while it is full.
define void @l0_pl011_put(i64 %base, i8 %c) {
entry:
  %fa = add i64 %base, 24
  %fp = inttoptr i64 %fa to ptr
  br label %wait
wait:
  %fr = load volatile i32, ptr %fp
  %full = and i32 %fr, 32
  %busy = icmp ne i32 %full, 0
  br i1 %busy, label %wait, label %send
send:
  %dp = inttoptr i64 %base to ptr
  store volatile i8 %c, ptr %dp
  ret void
}
