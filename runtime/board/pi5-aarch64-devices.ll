; pi5-aarch64-devices.ll -- the board's devices, written by tools/boards.l0 from
; runtime/board/pi5-aarch64.devices; change that, never this, and write it again:
;   tools/l0 run tools/boards.l0 -- ir pi5-aarch64 < runtime/board/pi5-aarch64.devices

@devices = private constant [30 x i64] [
  i64 70816632832, i64 4096,  ; 0x107D001000, the debug UART, a PL011
  i64 70799863808, i64 4096,  ; 0x107C003000, the 1 MHz system timer
  i64 70799931520, i64 64,  ; 0x107C013880, the VideoCore mailbox
  i64 133143986176, i64 4276224,  ; 0x1F00000000, RP1's BAR1, BAR2, BAR0
  i64 70805618688, i64 106496,  ; 0x107C580000, the HVS
  i64 68719497728, i64 128,  ; 0x1000005200, iommu4, the HVS's IOMMU
  i64 68719500032, i64 128,  ; 0x1000005B00, iommuc, the IOMMUs' cache
  i64 68720656384, i64 37648,  ; 0x1000120000, the PCIe controller of RP1
  i64 70807191552, i64 18432,  ; 0x107C700000, HDMI0's blocks, one run
  i64 70807322624, i64 256,  ; 0x107C720000, the HD block
  i64 70804111360, i64 256,  ; 0x107C410000, pixel valve 0
  i64 70821904896, i64 88,  ; 0x107D508200, DDC0
  i64 68719543808, i64 256,  ; 0x1000010600, dma40's channel 6
  i64 68736249856, i64 1536,  ; 0x1000FFF000, sdio1, SDHCI and cfg
  i64 70805102592, i64 48 ]  ; 0x107C502000, disp_intr

define i64 @l0_board_device_count() {
entry:
  ret i64 15
}

define i64 @l0_board_device_base(i64 %k) {
entry:
  %i = mul i64 %k, 2
  %p = getelementptr [30 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @l0_board_device_len(i64 %k) {
entry:
  %i0 = mul i64 %k, 2
  %i = add i64 %i0, 1
  %p = getelementptr [30 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}
