; virt-riscv64-devices.ll -- the board's devices, written by tools/boards.l0 from
; runtime/board/virt-riscv64.devices; change that, never this, and write it again:
;   tools/l0 run tools/boards.l0 -- ir virt-riscv64 < runtime/board/virt-riscv64.devices

@devices = private constant [8 x i64] [
  i64 268435456, i64 256,  ; 0x10000000, the 16550
  i64 1052672, i64 4096,  ; 0x00101000, the goldfish RTC
  i64 269484032, i64 24,  ; 0x10100000, firmware configuration
  i64 268439552, i64 32768 ]  ; 0x10001000, 8 virtio-mmio transports

define i64 @l0_board_device_count() {
entry:
  ret i64 4
}

define i64 @l0_board_device_base(i64 %k) {
entry:
  %i = mul i64 %k, 2
  %p = getelementptr [8 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @l0_board_device_len(i64 %k) {
entry:
  %i0 = mul i64 %k, 2
  %i = add i64 %i0, 1
  %p = getelementptr [8 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}
