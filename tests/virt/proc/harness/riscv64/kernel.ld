/* kernel.ll's image, for QEMU's riscv64 virt board with -m 1G, where
   OpenSBI enters it. */
ENTRY(_start)
SECTIONS
{
  . = 0x80200000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) }
  .bss : { *(.sbss*) *(.bss*) *(COMMON) }
  __image_end = .;
  __stack_top = 0x8FF00000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x8FE00000, "the image runs into the kernel's stack")
