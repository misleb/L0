/* The image layout for QEMU's aarch64 virt board, run with -m 2G, linked
   to a raw image the arm64 boot protocol loads at 0x40080000.
   runtime/board/virt-aarch64.ll has the memory map, and runtime/bare/
   board.ll, runtime/arch/aarch64/boot.ll, and runtime/freestanding.ll use
   every symbol below. */
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
  __input_len = 0x4FFFFFF8;
  __input_start = 0x50000000;
  __heap_start = 0x58000000;
  __heap_end = 0x98000000;
  __frames_start = 0x98000000;
  __frames_end = 0xB0000000;
  __stack_bottom = 0xB0000000;
  __stack_top = 0xC0000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x48000000, "the image overlaps QEMU's device tree")
ASSERT(__frames_end - __frames_start <= 98304 * 4096, "the pool is over 98,304 frames")
