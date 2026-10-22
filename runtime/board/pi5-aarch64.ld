/* The image layout for the Raspberry Pi 5, linked to a raw image its
   firmware loads at 0x80000, kernel_address, and enters at EL2 by the arm64
   boot protocol. runtime/board/pi5-aarch64.ll has the memory map, and
   runtime/bare/board.ll, runtime/arch/aarch64/boot.ll, and
   runtime/freestanding.ll use every symbol below. __l0_board is the image
   header's tag of the board, "pi5". The board has no loader: standard input
   is the initramfs the firmware puts at 0x10000000, which the device tree
   says the end of, so __input_len is a word that is always 0, which the
   host reads where it finds no initrd. It is a template (spec section
   10.3): tools/l0 puts __l0_heap_size and __l0_stack_size before it, the
   manifest's sizes or --heap-mb's and --stack-mb's, and its checks
   after. */
ENTRY(_start)
SECTIONS
{
  . = 0x80000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .input_len : { . = ALIGN(8); __input_len = .; QUAD(0) }
  . = ALIGN(8);
  __bss_start = .;
  .bss : { *(.bss*) *(COMMON) }
  . = ALIGN(8);
  __bss_end = .;
  __image_end = .;
  __image_size = 0x7F80000;
  __l0_board = 0x356970;
  __input_start = 0x10000000;
  __heap_start = 0x40000000;
  __heap_end = __heap_start + __l0_heap_size;
  __stack_top = 0x80000000;
  __stack_bottom = __stack_top - __l0_stack_size;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x08000000, "the image overlaps the device tree")
