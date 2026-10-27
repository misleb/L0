/* The layout of an L0 program run as a process, spec section 10.3, for
   runtime/bare/proc.ll and runtime/freestanding.ll, which use every symbol
   below, on every CPU. Every process runs at these virtual addresses, each in an address
   space of its own; where the kernel puts it in physical memory is the
   kernel's to choose. The image is an ELF with a PT_LOAD for each
   permission, which the target's manifest links with
   -z max-page-size=4096, so each segment is page-aligned in the file as in
   memory, and the heap starts at the first page after the image. The GOT
   is named in .data, since ld.lld puts an unnamed one after .bss, which
   writes .bss's zeros into the file and leaves the GOT past __image_end. */
ENTRY(_start)
PHDRS
{
  text   PT_LOAD FLAGS(5);                 /* PF_R | PF_X */
  rodata PT_LOAD FLAGS(4);                 /* PF_R */
  data   PT_LOAD FLAGS(6);                 /* PF_R | PF_W */
}
SECTIONS
{
  . = 0xC0000000;
  .text : { *(.text.boot) *(.text*) } :text
  . = ALIGN(4096);
  .rodata : { *(.rodata*) *(.srodata*) } :rodata
  . = ALIGN(4096);
  .data : { *(.data*) *(.sdata*) *(.got) *(.got.plt) } :data
  .bss : { *(.sbss*) *(.bss*) *(COMMON) } :data
  __image_end = .;
  __heap_start = ALIGN(__image_end, 4096);
  __heap_end = 0xD8000000;
  __stack_bottom = 0xD8000000;
  __stack_top = 0xE8000000;
  /DISCARD/ : { *(.eh_frame*) }
}
ASSERT(__image_end <= 0xD0000000, "the image leaves the heap less than 128 MB")
