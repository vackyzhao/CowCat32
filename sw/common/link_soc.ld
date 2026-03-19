OUTPUT_ARCH("riscv")
ENTRY(_start)

/*
 * CowCat32 SoC link map for Harvard-style execution:
 * - .text executes from ROM / IMEM
 * - .rodata / .data / .bss live in RAM / DMEM at runtime
 * - .rodata and .data are preloaded into DMEM by the reset-time boot copy
 *   engine before CPU reset is released
 */
MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 8K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
  } > ROM

  .rodata : {
    . = ALIGN(4);
    __rodata_start = .;
    *(.rodata .rodata.*)
    . = ALIGN(4);
    __rodata_end = .;
  } > RAM

  .data : {
    . = ALIGN(4);
    __data_start = .;
    *(.data .data.*)
    . = ALIGN(4);
    __data_end = .;
  } > RAM

  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  __stack_top = ORIGIN(RAM) + LENGTH(RAM) - 4;
}
