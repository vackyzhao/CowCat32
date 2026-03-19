/* Minimal CRT0 for CowCat32 SoC (rv32i, ilp32)
 * - set stack
 * - copy .data from ROM to RAM
 * - clear .bss
 * - call main
 */

.section .text.init
.globl _start
_start:
    /* set stack */
    la   sp, __stack_top

    /* copy .rodata */
    la   t0, __rodata_load
    la   t1, __rodata_start
    la   t2, __rodata_end
1:
    beq  t1, t2, 2f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    1b

2:
    /* copy .data */
    la   t0, __data_load
    la   t1, __data_start
    la   t2, __data_end
3:
    beq  t1, t2, 4f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    3b

4:
    /* clear .bss */
    la   t1, __bss_start
    la   t2, __bss_end
5:
    beq  t1, t2, 6f
    sw   zero, 0(t1)
    addi t1, t1, 4
    j    5b

6:
    call main

    /* if main returns: call _exit(main_ret) */
    call _exit
5:
    j    5b
