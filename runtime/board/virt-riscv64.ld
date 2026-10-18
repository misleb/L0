/* The image layout for QEMU's riscv64 virt board, run with -m 3G, linked
   to a raw image OpenSBI enters at 0x80200000. runtime/board/
   virt-riscv64.ll has the memory map, with the pool of frames in the 5th
   gigabyte, which it gives as numbers, since medany code cannot reach so
   far by an address; runtime/bare/board.ll, runtime/arch/riscv64/boot.ll,
   and runtime/freestanding.ll use every symbol below. RISC-V's small-data
   sections are collected with the others, so the boot code zeroes .sbss
   with .bss. */
ENTRY(_start)
SECTIONS
{
  . = 0x80200000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) }
  . = ALIGN(8);
  __bss_start = .;
  .bss : { *(.sbss*) *(.bss*) *(COMMON) }
  . = ALIGN(8);
  __bss_end = .;
  __image_end = .;
  __image_size = 0x3DFFFF8;
  __input_len = 0x83FFFFF8;
  __input_start = 0x84000000;
  __heap_start = 0x8C000000;
  __heap_end = 0xAC000000;
  __stack_bottom = 0xAC000000;
  __stack_top = 0xBC000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x83FFFFF8, "the image overlaps standard input")
