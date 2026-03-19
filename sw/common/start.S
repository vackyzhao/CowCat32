/* Minimal CRT0 for CowCat32 SoC (rv32i, ilp32)
 * - set stack
 * - clear .bss
 * - call main
 *
 * NOTE: .rodata/.data are expected to be initialized into DMEM by the
 * reset-time boot copy engine before CPU reset is released.
 */

.section .text.init
.globl _start
_start:
    /* set stack */
    la   sp, __stack_top

    /* clear .bss */
    la   t1, __bss_start
    la   t2, __bss_end
1:
    beq  t1, t2, 2f
    sw   zero, 0(t1)
    addi t1, t1, 4
    j    1b

2:
    call main

    /* if main returns: call _exit(main_ret) */
    call _exit
3:
    j    3b
