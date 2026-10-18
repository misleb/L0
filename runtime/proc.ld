/* The layout of an L0 program run as a process, spec section 10.3, for
   runtime/bare/proc.ll and runtime/freestanding.ll, which use every symbol
   below, on every CPU. Every process runs at these virtual addresses, each in an address
   space of its own; where the kernel puts it in physical memory is the
   kernel's to choose. */
ENTRY(_start)
SECTIONS
{
  . = 0xC0000000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) }
  .bss : { *(.sbss*) *(.bss*) *(COMMON) }
  __image_end = .;
  __heap_start = 0xC0400000;
  __heap_end = 0xD8000000;
  __stack_bottom = 0xD8000000;
  __stack_top = 0xE8000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0xC0400000, "the image is over 4 MB")
