/* QEMU virt: RAM starts at 0x40000000, and QEMU puts the device tree at
   its base, so the image starts above it. */
ENTRY(_start)
SECTIONS
{
  . = 0x40080000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  . = ALIGN(16);
  . = . + 0x100000;
  __stack_top = .;
}
