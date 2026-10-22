; virt-aarch64.ll -- QEMU's aarch64 virt board, as runtime/bare/board.ll
; asks a board's part: what the board has and where, spec section 10.3's
; tables for it. runtime/board/virt-aarch64.ld lays out its memory, and
; runtime/targets/virt-aarch64 lists the parts linked with this one. It
; carries no triple, but its descriptors are arm64's, since a board has one
; CPU.
;
; Memory, with QEMU's -m 2G (RAM is 0x40000000 to 0xC0000000):
;   0x40080000  the image: code, data, bss, which the boot code zeroes
;   0x48000000  the device tree, where QEMU puts it for the arm64 boot
;               protocol; the image must end below it, and the arguments
;               are copied out of it before the program starts
;   0x4FFFFFF8  standard input's length, a word, written by QEMU's loader
;   0x50000000  standard input's bytes, loaded by QEMU's loader
;   0x58000000  the heap, to 0x98000000
;   0x98000000  frames and the spaces' page tables, to 0xB0000000
;   0xB0000000  the stack, 256 MB, growing down from 0xC0000000
;   0xC0000000  to 0x100000000, the user range, mapped by each space alone
; Frames and tables come too from the image's end to the heap, but for the
; device tree and, until a read reaches their end, standard input's bytes.
;
; Standard output is the PL011 at 0x09000000. Standard error and the exit
; status reach the host by semihosting, so the three stay apart on a board
; with one serial line. Interrupts are the GICv2's, its distributor at
; 0x08000000 and its CPU interface at 0x08010000, which no program may open.

declare void @l0_pl011_put(i64, i8)
declare void @l0_gicv2_init(i64, i64)
declare void @l0_gicv2_enable(i64, i64)
declare i64 @l0_gicv2_take(i64)
declare void @l0_gicv2_end(i64, i64)
declare void @l0_semihost_exit(i64) noreturn
declare i64 @l0_semihost_err_write(ptr, i64)

; The boot map, which the boot code turns the MMU on with: the identity
; map in 1 GB blocks at level 1 (TCR T0SZ 25, 4 KB granule, 512 entries).
; Block 0 holds the devices, MAIR attribute 0, Device-nGnRnE; blocks 1 and 2
; are the RAM, attribute 1, normal write-back. With the MMU off every
; access would be to device memory, where an unaligned one faults. Block 3,
; the 4th gigabyte, is the user range, which only a space maps. Block 256,
; 0x4000000000, holds the PCIe ECAM, and is device memory as block 0 is.
; The rest, which the 39-bit translation reaches and this board has nothing
; the host gives in, is empty.
@l0_board_boot_map = global <{ [4 x i64], [252 x i64], i64, [255 x i64] }> <{ [4 x i64] [i64 1025, i64 1073743621, i64 2147485445, i64 0], [252 x i64] zeroinitializer, i64 274877907969, [255 x i64] zeroinitializer }>, align 4096

define void @l0_board_init(i64 %dtb, i64 %hart) {
entry:
  call void @l0_gicv2_init(i64 134217728, i64 134283264)
  ret void
}

; The RAM the device tree describes is all in the boot map already.
define void @l0_board_map_ram(i64 %lo, i64 %hi) {
entry:
  ret void
}

define void @l0_board_console_put(i8 %c) {
entry:
  call void @l0_pl011_put(i64 150994944, i8 %c)
  ret void
}

define i64 @l0_board_err_write(ptr %buf, i64 %n) {
entry:
  %r = call i64 @l0_semihost_err_write(ptr %buf, i64 %n)
  ret i64 %r
}

define void @l0_board_exit(i64 %status) noreturn {
entry:
  call void @l0_semihost_exit(i64 %status)
  unreachable
}

; The board's devices, spec section 10.3's table, as QEMU's virt board
; places them: a base and a length each. All are in block 0 of the boot
; map but the ECAM, in block 256, and both are device memory,
; Device-nGnRnE, so an access goes to the device at its width and in
; order. Anything else, RAM and the runtime's heap among it, is no region,
; and so is any range of the flash, the PCIe port-I/O and 64-bit windows,
; or the gaps between devices, where QEMU would answer an access with an
; external abort, and so is the GIC, which this file drives.
@devices = private constant [14 x i64] [
  i64 150994944, i64 4096,        ; 0x09000000, the PL011
  i64 151060480, i64 4096,        ; 0x09010000, the PL031
  i64 151126016, i64 24,          ; 0x09020000, firmware configuration
  i64 151191552, i64 4096,        ; 0x09030000, the PL061
  i64 167772160, i64 16384,       ; 0x0A000000, 32 virtio-mmio transports
  i64 268435456, i64 788463616,   ; 0x10000000, the PCIe 32-bit MMIO window
  i64 275146342400, i64 268435456 ] ; 0x4010000000, the PCIe ECAM

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

; A new space's root table, at l1: blocks 0 to 2 as the boot map has them,
; but for EL1 alone and never executable at EL0, and the devices' never at
; EL1 either, and block 3, the user range, through the table at l2. Block
; 256, the ECAM's, is as block 0.
define void @l0_board_space_init(i64 %l1, i64 %l2) {
entry:
  %p0 = inttoptr i64 %l1 to ptr
  store i64 27021597764224001, ptr %p0                      ; devices, EL1
  %p1 = getelementptr i64, ptr %p0, i64 1
  store i64 18014399583225605, ptr %p1                      ; RAM, EL1
  %p2 = getelementptr i64, ptr %p0, i64 2
  store i64 18014400656967429, ptr %p2
  %p3 = getelementptr i64, ptr %p0, i64 3
  %d3 = or i64 %l2, 3                                       ; the user range
  store i64 %d3, ptr %p3
  %p256 = getelementptr i64, ptr %p0, i64 256
  store i64 27021872642130945, ptr %p256                    ; the ECAM, EL1
  ret void
}

; The frame windows, spec section 10.3: what the layout leaves besides the
; image, the heap, and the stack, from the image's end to the heap and from
; the heap's end to the stack. The device tree and standard input are in the
; first, and runtime/bare/board.ll cuts them out.
@__image_end = external global i8
@__heap_start = external global i8
@__heap_end = external global i8
@__stack_bottom = external global i8

define i64 @l0_board_window_count() {
entry:
  ret i64 2
}

define i64 @l0_board_window_start(i64 %k) {
entry:
  %a = ptrtoint ptr @__image_end to i64
  %b = ptrtoint ptr @__heap_end to i64
  %first = icmp eq i64 %k, 0
  %r = select i1 %first, i64 %a, i64 %b
  ret i64 %r
}

define i64 @l0_board_window_end(i64 %k) {
entry:
  %a = ptrtoint ptr @__heap_start to i64
  %b = ptrtoint ptr @__stack_bottom to i64
  %first = icmp eq i64 %k, 0
  %r = select i1 %first, i64 %a, i64 %b
  ret i64 %r
}

; ------------------------------------------------------------- interrupts
;
; Interrupt 0 is the virtual timer's, the GIC's 27; a device's number is
; its GIC ID: the PL011's, PL031's, and PL061's are 33, 34, and 39, and the
; virtio-mmio transports' 48 to 79.

define i1 @l0_board_irq_exists(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  %uart = icmp eq i64 %n, 33
  %rtc = icmp eq i64 %n, 34
  %gpio = icmp eq i64 %n, 39
  %lo = icmp sge i64 %n, 48
  %hi = icmp sle i64 %n, 79
  %virtio = and i1 %lo, %hi
  %a = or i1 %timer, %uart
  %b = or i1 %rtc, %gpio
  %c = or i1 %a, %b
  %ok = or i1 %c, %virtio
  ret i1 %ok
}

define internal i64 @gic_id(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  %id = select i1 %timer, i64 27, i64 %n
  ret i64 %id
}

define void @l0_board_irq_enable(i64 %n) {
entry:
  %id = call i64 @gic_id(i64 %n)
  call void @l0_gicv2_enable(i64 134217728, i64 %id)
  ret void
}

define i64 @l0_board_irq_take() {
entry:
  %id = call i64 @l0_gicv2_take(i64 134283264)
  %timer = icmp eq i64 %id, 27
  %n = select i1 %timer, i64 0, i64 %id
  ret i64 %n
}

define void @l0_board_irq_end(i64 %n) {
entry:
  %id = call i64 @gic_id(i64 %n)
  call void @l0_gicv2_end(i64 134283264, i64 %id)
  ret void
}
