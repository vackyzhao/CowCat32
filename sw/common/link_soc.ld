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
  /* Default: 2048 words = 8KiB for both ROM/RAM (FPGA-friendly). */
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 8K
}

SECTIONS
{
  /* code + const in ROM */
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
  } > ROM

  /* rodata is accessed by the CPU data path, so place it in RAM at runtime
   * and store its load image in ROM with the instruction image. */
  .rodata : AT(ADDR(.text) + SIZEOF(.text)) {
    __rodata_start = .;
    *(.rodata .rodata.*)
    __rodata_end = .;
  } > RAM
  __rodata_load = LOADADDR(.rodata);

  /* data in RAM, load image stored in ROM right after rodata */
  .data : AT(LOADADDR(.rodata) + SIZEOF(.rodata)) {
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

  /* stack top at end of RAM (keep within physical SRAM window) */
  __stack_top = ORIGIN(RAM) + LENGTH(RAM) - 4;
}
