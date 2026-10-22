/* A layout of a program's own for QEMU's aarch64 virt board whose stack
   overlaps its heap, which the driver's checks refuse (spec section 10.3). */
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
  __heap_end = 0x60000000;
  __stack_bottom = 0x5C000000;
  __stack_top = 0x64000000;
  /DISCARD/ : { *(.eh_frame*) }
}
