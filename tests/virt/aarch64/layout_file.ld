/* A layout of a program's own for QEMU's aarch64 virt board, as
   --layout takes one (spec section 10.3): runtime/board/virt-aarch64.ld's,
   but with the stack right after the heap, both sized by what the driver
   puts before this, so all the RAM above them is frames. */
ENTRY(_start)
SECTIONS
{
  . = 0x40080000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  . = ALIGN(8);
  __bss_start = .;
  .bss : { *(.bss*) *(COMMON) }
  . = ALIGN(8);
  __bss_end = .;
  __image_end = .;
  __image_size = 0x7F80000;
  __l0_board = 0;
  __input_len = 0x4FFFFFF8;
  __input_start = 0x50000000;
  __heap_start = 0x58000000;
  __heap_end = __heap_start + __l0_heap_size;
  __stack_bottom = __heap_end;
  __stack_top = __stack_bottom + __l0_stack_size;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x48000000, "the image overlaps QEMU's device tree")
