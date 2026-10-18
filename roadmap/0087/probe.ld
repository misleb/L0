/* 0087's probe, linked to a raw image loaded at 0x80200000, where OpenSBI
   enters the next stage on QEMU's riscv64 virt board. The small-data
   sections, which RISC-V has and aarch64 does not, are collected with the
   others. */
ENTRY(_start)
SECTIONS
{
  . = 0x80200000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) }
  .bss : { *(.sbss*) *(.bss*) *(COMMON) }
  __image_end = .;
  /DISCARD/ : { *(.eh_frame*) }
}
