; pi5-aarch64.ll -- the Raspberry Pi 5, as runtime/bare/board.ll asks a
; board's part: what the board has and where, spec section 10.3's tables for
; it. runtime/board/pi5-aarch64.ld lays out its memory, and
; runtime/targets/pi5-aarch64.target lists the parts linked with this one. It
; carries no triple, but its descriptors are arm64's, since a board has one
; CPU. QEMU has no Raspberry Pi 5, so it runs only on a board, through
; tools/pi5-run.
;
; Memory, on a board with 2 GB or more (RAM from 0; on a 2 GB board the
; device tree's /memory is 0 to 0x3FC00000, or to 0x3F800000 when the
; firmware has an HDMI framebuffer above that, and 0x40000000 to
; 0x80000000, and reserves BL31's pages below 0x80000 apart, in
; /reserved-memory/atf@0):
;   0x00000000  BL31, the firmware's resident secure monitor, to 0x80000
;   0x00080000  the image: code, data, bss, which the boot code zeroes; the
;               firmware loads it there, kernel_address, and enters it at EL2
;   0x08000000  the device tree, device_tree_address; the image must end
;               below it, and the arguments are copied out of it before the
;               program starts
;   0x10000000  standard input's bytes, the initramfs the firmware loaded,
;               which the device tree says the place and end of
;   0x40000000  the heap, 768 MB unless --heap-mb gives its size
;   ...         frames and the spaces' page tables
;   0x70000000  the stack, 256 MB unless --stack-mb gives its size, growing
;               down from 0x80000000
;   0x80000000  more frames, when there is RAM there, to the user range
;   0xC0000000  to 0x100000000, the low user range, mapped by each space
;               alone, as the high one is, 0x2000000000 to 0x4000000000,
;               past every device: the RAM there is never used
;   0x100000000 frames and the spaces' page tables, to 0x400000000, where
;               there is RAM; the board has up to 16 GB
; Frames and tables come from all the RAM but the user range, BL31, the
; image, the heap, the stack, the device tree, and, until a read reaches
; their end, standard input's bytes.
; The boot map holds blocks 0 and 1 and the devices', so that the boot stack
; and the heap are mapped, and the rest of the RAM the device tree describes
; is added by l0_board_map_ram, so that a block with no RAM is never mapped
; as memory.
;
; Standard output and standard error are the debug UART, a PL011 that the
; firmware leaves set up, on the board's 3-pin connector; they are not
; apart, since the board has one serial line and no semihosting. The exit
; status reaches no host, so a status that is not 0 is written on the UART
; as "l0: exit status N", which is drained, and the board is powered off by
; PSCI. Interrupts are the GIC-400's, a GICv2, its distributor at
; 0x107FFF9000 and its CPU interface at 0x107FFFA000, which no program may
; open; the firmware leaves its interrupts in the non-secure group. PCIe's
; MSIs reach it through mip0, at 0x1000130000, which no program may open
; either: a write of n to the bus address 0xFF_FFFFF000 is its SPI 0x80 + n,
; the GIC's 160 + n.

declare void @l0_pl011_put(i64, i8)
declare void @l0_pl011_drain(i64)
declare void @l0_gicv2_init(i64, i64)
declare void @l0_gicv2_enable(i64, i64)
declare void @l0_gicv2_edge(i64, i64)
declare i64 @l0_gicv2_take(i64)
declare void @l0_gicv2_end(i64, i64)
declare i64 @l0_gicv2_self(i64)
declare void @l0_gicv2_wake(i64, i64)
declare void @l0_psci_off() noreturn
declare void @l0_psci_reset() noreturn

; The boot map, which the boot code turns the MMU on with: the identity map
; in 1 GB blocks at level 1 (TCR T0SZ 25, 4 KB granule, 512 entries). Block
; 0 and 1, the first 2 GB of RAM, are normal memory, MAIR attribute 1,
; write-back, inner shareable, readable and writable at EL1 alone and never
; executable at EL0. Block 65, 0x1040000000, holds every device the board's
; part drives or opens but those in block 64, 0x1000000000, the IOMMUs, the
; PCIe controller, dma40, mip0, and sdio1, and RP1's, in block 124, 0x1F00000000: all
; three attribute 0, Device-nGnRnE, never executable. Block
; 3, the low user range, and blocks 128 to 255, the high one, are left
; empty, and only a space maps them; so is every block with no RAM in it
; until l0_board_map_ram adds it, which adds none past the 64th.
@l0_board_boot_map = global <{ i64, i64, [62 x i64], i64, i64, [58 x i64], i64, [387 x i64] }> <{ i64 18014398509483781, i64 18014399583225605, [62 x i64] zeroinitializer, i64 27021666483700737, i64 27021667557442561, [58 x i64] zeroinitializer, i64 27021730908210177, [387 x i64] zeroinitializer }>, align 4096

; The debug UART, and the GIC's distributor and CPU interface.
@uart_irq = internal global i64 153

; Besides the GIC, the path of PCIe's MSIs, which the firmware leaves
; unmapped: the controller's third inbound window, its RC_BAR3 at 0x403C
; and 0x4040 and its UBUS remap at 0x40BC and 0x40C0, takes the bus
; address 0xFF_FFFFF000, 4 KB (size code 0x1C), to mip0 at 0x1000130000,
; with access enabled; and mip0's vectors, which the firmware leaves
; level-triggered and open to the VideoCore too, are made edge-triggered
; (CFGL and CFGH_HOST, 0x20 and 0x30), open to the CPU (MASKL and
; MASKH_HOST, 0x40 and 0x50), and masked for the VideoCore (0x60, 0x70),
; as Linux's irq-bcm2712-mip.c sets them. The GIC still has each disabled
; until a program enables it.
define void @l0_board_init(i64 %dtb, i64 %hart) {
entry:
  call void @l0_gicv2_init(i64 70866931712, i64 70866935808)
  store volatile i32 -4068, ptr inttoptr (i64 68720672828 to ptr)     ; 0xFFFFF01C
  store volatile i32 255, ptr inttoptr (i64 68720672832 to ptr)       ; 0xFF
  store volatile i32 1245185, ptr inttoptr (i64 68720672956 to ptr)   ; 0x00130001
  store volatile i32 16, ptr inttoptr (i64 68720672960 to ptr)        ; 0x10
  store volatile i32 -1, ptr inttoptr (i64 68720721952 to ptr)
  store volatile i32 -1, ptr inttoptr (i64 68720721968 to ptr)
  store volatile i32 0, ptr inttoptr (i64 68720721984 to ptr)
  store volatile i32 0, ptr inttoptr (i64 68720722000 to ptr)
  store volatile i32 -1, ptr inttoptr (i64 68720722016 to ptr)
  store volatile i32 -1, ptr inttoptr (i64 68720722032 to ptr)
  call void asm sideeffect "dsb sy", "~{memory}"()
  ret void
}

; Another CPU, as it starts: its own CPU interface, banked at the same
; address, and its own virtual timer's interrupt, banked in the
; distributor, which is on already.
define void @l0_board_cpu_init() {
entry:
  call void @l0_gicv2_init(i64 70866931712, i64 70866935808)
  call void @l0_gicv2_enable(i64 70866931712, i64 27)
  ret void
}

; How the calling CPU is woken, and waking one: the GIC's SGI 0.
define i64 @l0_board_cpu_target() {
entry:
  %t = call i64 @l0_gicv2_self(i64 70866931712)
  ret i64 %t
}

define void @l0_board_cpu_wake(i64 %t) {
entry:
  call void @l0_gicv2_wake(i64 70866931712, i64 %t)
  ret void
}

; Adds the 1 GB blocks of the RAM from lo to hi to the boot map, but for the
; low user range, which no RAM is in, and for the blocks past the 64th, which
; are none of the board's, and makes the stores seen before any is used.
; Going from invalid to valid needs no TLB maintenance.
define void @l0_board_map_ram(i64 %lo, i64 %hi) {
entry:
  %empty = icmp uge i64 %lo, %hi
  br i1 %empty, label %done, label %go
go:
  %last0 = sub i64 %hi, 1
  %first = lshr i64 %lo, 30
  %last1 = lshr i64 %last0, 30
  %big = icmp ugt i64 %last1, 63
  %last = select i1 %big, i64 63, i64 %last1
  br label %loop
loop:
  %b = phi i64 [ %first, %go ], [ %b1, %next ]
  %more = icmp ule i64 %b, %last
  br i1 %more, label %one, label %fin
one:
  %user = icmp eq i64 %b, 3
  br i1 %user, label %next, label %put
put:
  %base = shl i64 %b, 30
  %d = or i64 %base, 18014398509483781
  %p = getelementptr [512 x i64], ptr @l0_board_boot_map, i64 0, i64 %b
  store i64 %d, ptr %p
  br label %next
next:
  %b1 = add i64 %b, 1
  br label %loop
fin:
  call void asm sideeffect "dsb ishst\0Aisb", "~{memory}"()
  br label %done
done:
  ret void
}

define void @l0_board_console_put(i8 %c) {
entry:
  call void @l0_pl011_put(i64 70816632832, i8 %c)
  ret void
}

; Standard error is the same line as standard output.
define i64 @l0_board_err_write(ptr %buf, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr i8, ptr %buf, i64 %i
  %c = load i8, ptr %p
  call void @l0_pl011_put(i64 70816632832, i8 %c)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %n
}

@m_status = private constant [16 x i8] c"l0: exit status "

; Writes the decimal digits of v, with a minus sign if it is negative.
define internal void @put_dec(i64 %v) {
entry:
  %buf = alloca [24 x i8]
  %neg = icmp slt i64 %v, 0
  %nv = sub i64 0, %v
  %m = select i1 %neg, i64 %nv, i64 %v
  br i1 %neg, label %sign, label %loop
sign:
  call void @l0_pl011_put(i64 70816632832, i8 45)
  br label %loop
loop:
  %x = phi i64 [ %m, %entry ], [ %m, %sign ], [ %q, %loop ]
  %n = phi i64 [ 0, %entry ], [ 0, %sign ], [ %n1, %loop ]
  %q = udiv i64 %x, 10
  %r = urem i64 %x, 10
  %c = add i64 %r, 48
  %c8 = trunc i64 %c to i8
  %p = getelementptr [24 x i8], ptr %buf, i64 0, i64 %n
  store i8 %c8, ptr %p
  %n1 = add i64 %n, 1
  %again = icmp ne i64 %q, 0
  br i1 %again, label %loop, label %emit
emit:
  %k = phi i64 [ %n1, %loop ], [ %k1, %emit ]
  %k1 = sub i64 %k, 1
  %ep = getelementptr [24 x i8], ptr %buf, i64 0, i64 %k1
  %ch = load i8, ptr %ep
  call void @l0_pl011_put(i64 70816632832, i8 %ch)
  %left = icmp ne i64 %k1, 0
  br i1 %left, label %emit, label %done
done:
  ret void
}

; Stops the program: a status that is not 0 is reported on the line, the
; line is drained, and the firmware powers the board off, which halts it.
define void @l0_board_exit(i64 %status) noreturn {
entry:
  %nz = icmp ne i64 %status, 0
  br i1 %nz, label %report, label %off
report:
  %e = call i64 @l0_board_err_write(ptr @m_status, i64 16)
  call void @put_dec(i64 %status)
  call void @l0_pl011_put(i64 70816632832, i8 10)
  br label %off
off:
  call void @l0_pl011_drain(i64 70816632832)
  call void @l0_psci_off()
  unreachable
}

; Spec section 6.12: the serial line drained, as an exit does, and the
; firmware asked to reset the board. It does not return.
define i64 @l0_board_restart() {
entry:
  call void @l0_pl011_drain(i64 70816632832)
  call void @l0_psci_reset()
  unreachable
}

; The board's devices, spec section 10.3's table, as the device tree
; places them: a base and a length each, in blocks 64, 65 and 124 of the
; boot map, which are device memory. RP1's window answers, but a first run
; read 0xDEADDEAD in it, so it holds RP1 only once a driver has set the
; PCIe controller's outbound window and RP1's BAR, through the controller,
; which is a region for that; and the HVS scans out HDMI0 as the firmware
; set it up. RP1's region holds its BAR1, its peripherals, 4 MB at PCI 0,
; then its BAR2, 64 KB, and BAR0, 16 KB, its MSI-X table, where a driver
; puts them, at PCI 0x400000 and 0x410000. Anything else, RAM and the
; runtime's heap among it, is no region, and so are the GIC and mip0,
; which this file drives, and so are iommu2 and iommu5, beside iommu4.
; HDMI0's mode set takes four more, all in block 65: its blocks, the HD
; block, pixel valve 0, and DDC0 (roadmap 0120). HDMI0's audio takes
; channel 6 of dma40, in block 64, to feed the MAI (roadmap 0122). The
; microSD slot takes sdio1, its SDHCI and cfg block in one run, in block
; 64 (roadmap 0125). The HVS's end of frame takes disp_intr, the display's
; interrupt controller, in block 65 (roadmap 0127).
@devices = private constant [30 x i64] [
  i64 70816632832, i64 4096,      ; 0x107D001000, the debug UART, a PL011
  i64 70799863808, i64 4096,      ; 0x107C003000, the 1 MHz system timer
  i64 70799931520, i64 64,        ; 0x107C013880, the VideoCore mailbox
  i64 133143986176, i64 4276224,  ; 0x1F00000000, RP1's BAR1, BAR2, BAR0
  i64 70805618688, i64 106496,    ; 0x107C580000, the HVS
  i64 68719497728, i64 128,       ; 0x1000005200, iommu4, the HVS's IOMMU
  i64 68719500032, i64 128,       ; 0x1000005B00, iommuc, the IOMMUs' cache
  i64 68720656384, i64 37648,     ; 0x1000120000, the PCIe controller of RP1
  i64 70807191552, i64 18432,     ; 0x107C700000, HDMI0's blocks, one run
  i64 70807322624, i64 256,       ; 0x107C720000, the HD block
  i64 70804111360, i64 256,       ; 0x107C410000, pixel valve 0
  i64 70821904896, i64 88,        ; 0x107D508200, DDC0
  i64 68719543808, i64 256,       ; 0x1000010600, dma40's channel 6
  i64 68736249856, i64 1536,      ; 0x1000FFF000, sdio1, SDHCI and cfg
  i64 70805102592, i64 48 ]       ; 0x107C502000, disp_intr

define i64 @l0_board_device_count() {
entry:
  ret i64 15
}

define i64 @l0_board_device_base(i64 %k) {
entry:
  %i = mul i64 %k, 2
  %p = getelementptr [16 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @l0_board_device_len(i64 %k) {
entry:
  %i0 = mul i64 %k, 2
  %i = add i64 %i0, 1
  %p = getelementptr [16 x i64], ptr @devices, i64 0, i64 %i
  %v = load i64, ptr %p
  ret i64 %v
}

; A new space's root table, at l1: every entry of the boot map, which is for
; EL1 alone, but the 4th, the low user range, which is the table at l2.
; The high user range's, empty in the boot map, stay empty until
; runtime/bare/board.ll maps a page there.
define void @l0_board_space_init(i64 %l1, i64 %l2) {
entry:
  %root = inttoptr i64 %l1 to ptr
  %user = or i64 %l2, 3
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %src = getelementptr [512 x i64], ptr @l0_board_boot_map, i64 0, i64 %i
  %v = load i64, ptr %src
  %is3 = icmp eq i64 %i, 3
  %d = select i1 %is3, i64 %user, i64 %v
  %dst = getelementptr i64, ptr %root, i64 %i
  store i64 %d, ptr %dst
  %i1 = add i64 %i, 1
  %more = icmp ult i64 %i1, 512
  br i1 %more, label %loop, label %done
done:
  ret void
}

; The frame windows, spec section 10.3: the RAM the boot map may reach but
; the low user range, from 0 up to 0xC0000000 and from the 5th gigabyte to the
; 16th, where the device tree says there is RAM. runtime/bare/board.ll
; cuts out BL31 and the image, below the image's end, the heap, the stack,
; the device tree, and standard input, wherever the layout puts them.
define i64 @l0_board_window_count() {
entry:
  ret i64 2
}

define i64 @l0_board_window_start(i64 %k) {
entry:
  %first = icmp eq i64 %k, 0
  %r = select i1 %first, i64 0, i64 4294967296             ; 0, 0x100000000
  ret i64 %r
}

define i64 @l0_board_window_end(i64 %k) {
entry:
  %first = icmp eq i64 %k, 0
  %r = select i1 %first, i64 3221225472, i64 17179869184   ; 0xC0000000, 0x400000000
  ret i64 %r
}

; ------------------------------------------------------------- interrupts
;
; Interrupt 0 is the virtual timer's, the GIC's 27; the system timer's four
; are its 96 to 99; the debug UART's is 153, which is 152 on the later
; silicon, so both are enabled, the one that fires is remembered, and it is
; reported as 153; PCIe's MSIs are 160 to 223, mip0's vectors, which are
; made edge-triggered as they are enabled; dma40's channel 6's is 118;
; disp_intr's, the HVS's end of frame among its lines, is 129; sdio1's is
; 305.

define internal i1 @is_msi(i64 %n) {
entry:
  %lo = icmp sge i64 %n, 160
  %hi = icmp sle i64 %n, 223
  %r = and i1 %lo, %hi
  ret i1 %r
}

define i1 @l0_board_irq_exists(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  %uart = icmp eq i64 %n, 153
  %dma = icmp eq i64 %n, 118
  %sd = icmp eq i64 %n, 305
  %disp = icmp eq i64 %n, 129
  %lo = icmp sge i64 %n, 96
  %hi = icmp sle i64 %n, 99
  %sys = and i1 %lo, %hi
  %msi = call i1 @is_msi(i64 %n)
  %a0 = or i1 %timer, %uart
  %a1 = or i1 %a0, %dma
  %a2 = or i1 %a1, %sd
  %a = or i1 %a2, %disp
  %b = or i1 %sys, %msi
  %ok = or i1 %a, %b
  ret i1 %ok
}

define void @l0_board_irq_enable(i64 %n) {
entry:
  %uart = icmp eq i64 %n, 153
  br i1 %uart, label %both, label %one
both:
  call void @l0_gicv2_enable(i64 70866931712, i64 152)
  call void @l0_gicv2_enable(i64 70866931712, i64 153)
  ret void
one:
  %msi = call i1 @is_msi(i64 %n)
  br i1 %msi, label %edge, label %enable
edge:
  call void @l0_gicv2_edge(i64 70866931712, i64 %n)
  br label %enable
enable:
  %timer = icmp eq i64 %n, 0
  %id = select i1 %timer, i64 27, i64 %n
  call void @l0_gicv2_enable(i64 70866931712, i64 %id)
  ret void
}

define i64 @l0_board_irq_take() {
entry:
  %id = call i64 @l0_gicv2_take(i64 70866935808)
  %timer = icmp eq i64 %id, 27
  %u152 = icmp eq i64 %id, 152
  %u153 = icmp eq i64 %id, 153
  %uart = or i1 %u152, %u153
  br i1 %uart, label %remember, label %other
remember:
  store i64 %id, ptr @uart_irq
  ret i64 153
other:
  %n = select i1 %timer, i64 0, i64 %id
  ret i64 %n
}

define void @l0_board_irq_end(i64 %n) {
entry:
  %timer = icmp eq i64 %n, 0
  %uart = icmp eq i64 %n, 153
  %fired = load i64, ptr @uart_irq
  %id0 = select i1 %timer, i64 27, i64 %n
  %id = select i1 %uart, i64 %fired, i64 %id0
  call void @l0_gicv2_end(i64 70866935808, i64 %id)
  ret void
}
