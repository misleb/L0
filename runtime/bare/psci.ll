; psci.ll -- a board with no emulator beneath it asks its firmware to power
; it off, by Arm's Power State Coordination Interface through an SMC, which
; the firmware's BL31 answers on a Raspberry Pi 5. QEMU's virt board has
; PSCI too, but by HVC, so only a board that wants this links it. It names
; its triple, since it is assembly. A board's part that has it calls it, after
; its serial port is drained, as the way to stop the program.

target triple = "aarch64-unknown-none-elf"

; SYSTEM_OFF, function 0x84000008, which does not return. On the Raspberry
; Pi 5 it halts the board until its power button is pressed; if the call
; does come back, the CPU waits for an interrupt, with them masked, forever.
define void @l0_psci_off() noreturn {
entry:
  call void asm sideeffect "mov x0, #0x8\0Amovk x0, #0x8400, lsl #16\0Asmc #0", "~{x0},~{x1},~{x2},~{x3},~{memory}"()
  br label %hang
hang:
  call void asm sideeffect "wfi", ""()
  br label %hang
}
