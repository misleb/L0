; virt-aarch64-devices.ll -- the board's devices, written by tools/boards.l0 from
; runtime/board/virt-aarch64.devices; change that, never this, and write it again:
;   tools/l0 run tools/boards.l0 -- ir virt-aarch64 < runtime/board/virt-aarch64.devices

@devices = private constant [14 x i64] [
  i64 150994944, i64 4096,  ; 0x09000000, the PL011
  i64 151060480, i64 4096,  ; 0x09010000, the PL031
  i64 151126016, i64 24,  ; 0x09020000, firmware configuration
  i64 151191552, i64 4096,  ; 0x09030000, the PL061
  i64 167772160, i64 16384,  ; 0x0A000000, 32 virtio-mmio transports
  i64 268435456, i64 788463616,  ; 0x10000000, the PCIe 32-bit MMIO window
  i64 275146342400, i64 268435456 ]  ; 0x4010000000, the PCIe ECAM

define i64 @l0_board_device_count() {
entry:
  ret i64 7
}

define i64 @l0_board_device_base(i64 %k) {
entry:
  %i = mul i64 %k, 2
  %p = getelementptr [14 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @l0_board_device_len(i64 %k) {
entry:
  %i0 = mul i64 %k, 2
  %i = add i64 %i0, 1
  %p = getelementptr [14 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}
