OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 512K
}

SECTIONS
{
  . = ORIGIN(RAM);

  .text.init : {
    *(.text.init)
  } > RAM

  .text : {
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.*)
  } > RAM

  .data : {
    *(.data .data.*)
  } > RAM

  .bss : {
    *(.bss .bss.*)
    *(COMMON)
  } > RAM

  /* tohost (for TB pass/fail) */
  .tohost 0x00001000 : {
    KEEP(*(.tohost))
  } > RAM
}
