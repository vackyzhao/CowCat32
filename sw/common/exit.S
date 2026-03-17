/*
 * _exit(code)
 * Default termination behavior for baremetal: park forever.
 * This compiles to a single-instruction infinite loop (jal x0, 0).
 *
 * If you want simulation to stop, write TOHOST yourself before returning.
 */

.section .text
.globl _exit
_exit:
1:
    j 1b
