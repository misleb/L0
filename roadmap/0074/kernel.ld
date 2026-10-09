/* kernel.ll's image, for QEMU's aarch64 virt board with -m 2G. */
ENTRY(_start)
SECTIONS
{
  . = 0x40080000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  __image_end = .;
  __stack_top = 0x4FF00000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x4FE00000, "the image runs into the kernel's stack")
