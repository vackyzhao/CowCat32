OUTPUT_ARCH("riscv")
ENTRY(_start)

/*
 * CowCat32 riscv-tests link script (RV32I, no privileged/CSR support).
 *
 * We run from address 0x0 (matches current blackbox TB PC reset).
 * Use a single unified memory image in the TB (imem+dmem share the same array).
 * Place tohost/fromhost/signature in RAM so pass/fail can be detected by a store.
 */

SECTIONS
{
  . = 0x00000000;

  .text.init : { *(.text.init) }
  .text      : { *(.text) *(.text.*) }
  .rodata    : { *(.rodata) *(.rodata.*) }

  /* Put tohost in RAM (word writes) */
  . = 0x00001000;
  .tohost : { *(.tohost) }

  . = 0x00002000;
  .data : { *(.data) *(.data.*) }
  .bss  : { *(.bss) *(.bss.*) *(COMMON) }

  /* Simple stack top */
  . = 0x00020000;
  _stack_top = .;
}
