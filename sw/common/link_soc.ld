OUTPUT_ARCH("riscv")
ENTRY(_start)

/*
 * Unified address map for toolchain (RISC-V has a single address space).
 * We therefore place ROM and RAM at different VMAs.
 *
 * NOTE (current RTL): DMEM SRAM index truncates high address bits, so
 * 0x2000_0000 aliases to physical SRAM[0]. This lets us keep a clean
 * link map without changing hardware decode yet.
 */
MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 512K
  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 512K
}

SECTIONS
{
  /* code + const in ROM */
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
  } > ROM

  .rodata : {
    *(.rodata .rodata.*)
  } > ROM

  /* data in RAM, load image stored in ROM */
  .data : AT(ADDR(.rodata) + SIZEOF(.rodata)) {
    __data_start = .;
    *(.data .data.*)
    __data_end = .;
  } > RAM
  __data_load = LOADADDR(.data);

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  /* stack top at end of RAM */
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
