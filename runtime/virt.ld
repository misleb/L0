/* The image layout for QEMU's aarch64 virt board, run with -m 2G, linked
   to a raw image the arm64 boot protocol loads at 0x40080000.
   runtime/host-virt.ll has the memory map, and uses every symbol below. */
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
  __heap_start = 0x58000000;
  __heap_end = 0x98000000;
  __frames_start = 0x98000000;
  __frames_end = 0xB0000000;
  __stack_bottom = 0xB0000000;
  __stack_top = 0xC0000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0x48000000, "the image overlaps QEMU's device tree")
