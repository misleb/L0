/* A process's layout, for proc.ll and fault.ll. Every process runs at the
   same virtual addresses, each in its own address space; __load, given by
   --defsym, is the physical address QEMU's loader puts its image at, which
   kernel.ll maps at 0xC0000000. */
ENTRY(_start)
SECTIONS
{
  . = 0xC0000000;
  .text : AT(__load) { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  __image_end = .;
  __heap_start = 0xC0400000;
  __heap_end = 0xD8000000;
  __stack_bottom = 0xD8000000;
  __stack_top = 0xE8000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0xC0400000, "the image is over 4 MB")
