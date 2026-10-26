; virt-riscv64.ll -- QEMU's riscv64 virt board, as runtime/bare/board.ll
; asks a board's part: what the board has and where, spec section 10.3's
; tables for it. runtime/board/virt-riscv64.ld lays out its memory, and
; runtime/targets/virt-riscv64 lists the parts linked with this one. It
; carries no triple, but its descriptors are Sv39's, since a board has one
; CPU. OpenSBI, QEMU's firmware, enters the image in S-mode.
;
; Memory, with QEMU's -m 3G (RAM is 0x80000000 to 0x140000000):
;   0x80000000  OpenSBI, which keeps it from S-mode
;   0x80200000  the image: code, data, bss, which the boot code zeroes
;   0x83FFFFF8  standard input's length, a word, written by QEMU's loader
;   0x84000000  standard input's bytes, loaded by QEMU's loader
;   0x8C000000  the heap, 512 MB unless --heap-mb gives its size
;   ...         frames and the spaces' page tables
;   0xAC000000  the stack, 256 MB unless --stack-mb gives its size, growing
;               down from 0xBC000000
;   0xBC000000  frames and tables, but for the device tree, which QEMU puts
;               at 0xBFE00000; the arguments are copied out of it before
;               the program starts
;   0xC0000000  to 0x100000000, the user range, mapped by each space alone:
;               the RAM there is never used
;   0x100000000 frames and the spaces' page tables, to 0x140000000
; Frames and tables come from all the RAM but the user range, OpenSBI, the
; image, the heap, the stack, the device tree, and standard input's bytes
; until a read reaches their end. The 5th gigabyte is past what code built
; for the medany model reaches by its address, so the windows give it as
; numbers.
;
; Standard output is the 16550 at 0x10000000. Standard error and the exit
; status reach the host by semihosting, so the three stay apart on a board
; with one serial line. Interrupts are the PLIC's, at 0x0C000000, which no
; program may open, and the timer's, the SBI's.

declare void @l0_ns16550_put(i64, i64, i8)
declare void @l0_plic_init(i64, i64)
declare void @l0_plic_enable(i64, i64, i64)
declare i64 @l0_plic_claim(i64, i64)
declare void @l0_plic_complete(i64, i64, i64)
declare void @l0_semihost_exit(i64) noreturn
declare i64 @l0_semihost_err_write(ptr, i64)
declare i1 @l0_riscv64_timer_pending()
declare void @l0_riscv64_sie_on(i64)
declare void @l0_riscv64_sie_off(i64)
declare i64 @l0_arch_pte_table(i64)

; The boot map, Sv39's root table, which the boot code turns translation on
; with: the identity map in 1 GB pages, global and for S-mode alone.
; Gigapage 0 holds the devices, read and write; 2 is the RAM below the user
; range, read, write, and execute; 4 the RAM above it, which the pool is in,
; read and write. Gigapage 1, the PCIe window, is not mapped, and 3, the 4th
; gigabyte, is the user range, which only a space maps.
@l0_board_boot_map = global <{ i64, i64, i64, i64, i64, [507 x i64] }> <{ i64 231, i64 0, i64 536871151, i64 0, i64 1073742055, [507 x i64] zeroinitializer }>, align 4096

; The PLIC's context for the booting hart's S-mode, 2 hart + 1 on QEMU,
; whose contexts go M, S for each hart in turn.
@plic_ctx = internal global i64 1

; The RAM the device tree describes is all in the boot map already.
define void @l0_board_map_ram(i64 %lo, i64 %hi) {
entry:
  ret void
}

define void @l0_board_init(i64 %dtb, i64 %hart) {
entry:
  %h2 = shl i64 %hart, 1
  %ctx = add i64 %h2, 1
  store i64 %ctx, ptr @plic_ctx
  call void @l0_plic_init(i64 201326592, i64 %ctx)
  ret void
}

; No other hart is started (spec section 10.3), so none is set up.
define void @l0_board_cpu_init() {
entry:
  ret void
}

define void @l0_board_console_put(i8 %c) {
entry:
  call void @l0_ns16550_put(i64 268435456, i64 0, i8 %c)
  ret void
}

define i64 @l0_board_err_write(ptr %buf, i64 %n) {
entry:
  %r = call i64 @l0_semihost_err_write(ptr %buf, i64 %n)
  ret i64 %r
}

; Spec section 6.12: this board has no reset to ask for.
define i64 @l0_board_restart() {
entry:
  ret i64 -3
}

define void @l0_board_exit(i64 %status) noreturn {
entry:
  call void @l0_semihost_exit(i64 %status)
  unreachable
}

; The device tree's timebase-frequency on QEMU's virt board.
define i64 @l0_board_timebase_hz() {
entry:
  ret i64 10000000
}

; The board's devices, spec section 10.3's table, as QEMU's virt board
; places them: a base and a length each. All are in gigapage 0 of the boot
; map, where the board's physical memory attributes make every access go to
; the device at its width and in order. Anything else is no region: RAM, the
; flash, the PCIe windows, the gaps between devices, and the PLIC and the
; CLINT, which the host and the SBI drive.
@devices = private constant [8 x i64] [
  i64 268435456, i64 256,         ; 0x10000000, the 16550
  i64 1052672, i64 4096,          ; 0x00101000, the goldfish RTC
  i64 269484032, i64 24,          ; 0x10100000, firmware configuration
  i64 268439552, i64 32768 ]      ; 0x10001000, 8 virtio-mmio transports

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

; A new space's root table, at l1: gigapages 0, 2, and 4 as the boot map
; has them, for S-mode alone, and 3, the user range, through the table at
; l2.
define void @l0_board_space_init(i64 %l1, i64 %l2) {
entry:
  %p0 = inttoptr i64 %l1 to ptr
  store i64 231, ptr %p0                                    ; devices
  %p2 = getelementptr i64, ptr %p0, i64 2
  store i64 536871151, ptr %p2                              ; RAM
  %p3 = getelementptr i64, ptr %p0, i64 3
  %d3 = call i64 @l0_arch_pte_table(i64 %l2)                ; the user range
  store i64 %d3, ptr %p3
  %p4 = getelementptr i64, ptr %p0, i64 4
  store i64 1073742055, ptr %p4                             ; RAM, the pool
  ret void
}

; The frame windows, spec section 10.3: the RAM the boot map reaches but
; the user range, 0x80000000 up to 0xC0000000 and the 5th gigabyte.
; runtime/bare/board.ll cuts out OpenSBI and the image, below the image's
; end, the heap, the stack, the device tree, and standard input, wherever
; the layout puts them.
define i64 @l0_board_window_count() {
entry:
  ret i64 2
}

define i64 @l0_board_window_start(i64 %k) {
entry:
  %first = icmp eq i64 %k, 0
  %r = select i1 %first, i64 2147483648, i64 4294967296    ; 0x80000000, 0x100000000
  ret i64 %r
}

define i64 @l0_board_window_end(i64 %k) {
entry:
  %first = icmp eq i64 %k, 0
  %r = select i1 %first, i64 3221225472, i64 5368709120    ; 0xC0000000, 0x140000000
  ret i64 %r
}

; ------------------------------------------------------------- interrupts
;
; Interrupt 0 is the timer's, the supervisor timer interrupt, which the
; SBI raises; a device's number is its PLIC source: the virtio-mmio
; transports' 1 to 8, the 16550's 10, and the RTC's 11. The timer is taken
; by masking it in sie until it is ended, since it stays pending until
; another deadline is set; a device's by the PLIC's claim, ended by its
; completion.

@timer_live = internal global i1 false

define i1 @l0_board_irq_exists(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  %lo = icmp sge i64 %n, 1
  %hi = icmp sle i64 %n, 8
  %virtio = and i1 %lo, %hi
  %uart = icmp eq i64 %n, 10
  %rtc = icmp eq i64 %n, 11
  %a = or i1 %timer, %virtio
  %b = or i1 %uart, %rtc
  %ok = or i1 %a, %b
  ret i1 %ok
}

define void @l0_board_irq_enable(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  br i1 %timer, label %t, label %dev
t:
  store i1 true, ptr @timer_live
  call void @l0_riscv64_sie_on(i64 32)
  ret void
dev:
  %ctx = load i64, ptr @plic_ctx
  call void @l0_plic_enable(i64 201326592, i64 %ctx, i64 %n)
  call void @l0_riscv64_sie_on(i64 512)
  ret void
}

; The timer's, if it is pending and not taken, before any device's.
define i64 @l0_board_irq_take() {
entry:
  %live = load i1, ptr @timer_live
  br i1 %live, label %check, label %dev
check:
  %p = call i1 @l0_riscv64_timer_pending()
  br i1 %p, label %timer, label %dev
timer:
  store i1 false, ptr @timer_live
  call void @l0_riscv64_sie_off(i64 32)
  ret i64 0
dev:
  %ctx = load i64, ptr @plic_ctx
  %id = call i64 @l0_plic_claim(i64 201326592, i64 %ctx)
  ret i64 %id
}

define void @l0_board_irq_end(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  br i1 %timer, label %t, label %dev
t:
  store i1 true, ptr @timer_live
  call void @l0_riscv64_sie_on(i64 32)
  ret void
dev:
  %ctx = load i64, ptr @plic_ctx
  call void @l0_plic_complete(i64 201326592, i64 %ctx, i64 %n)
  ret void
}
