/* The image layout for QEMU's aarch64 virt board, run with -m 2G.
   runtime/host-virt.ll has the memory map, and uses every symbol below. */
ENTRY(_start)
SECTIONS
{
  . = 0x40080000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  __image_end = .;
  __heap_start = 0x58000000;
  __heap_end = 0xB0000000;
  __stack_bottom = 0xB0000000;
  __stack_top = 0xC0000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x4FFFFFF8, "the image overlaps standard input")
