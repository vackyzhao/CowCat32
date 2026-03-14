// Minimal riscv-tests environment for CowCat32 (RV32I, no CSR/trap).
//
// The upstream riscv-tests "env/p" assumes privileged CSRs and uses ECALL.
// This header replaces that with a pure-RV32I environment:
// - No CSR reads/writes
// - PASS/FAIL by storing a word to `tohost`
// - `_start` at 0x0

#ifndef _COWCAT32_RISCV_TEST_H
#define _COWCAT32_RISCV_TEST_H

// XLEN-specific init macro (kept for compatibility with riscv-tests).
#define RVTEST_RV32U                                                    \
  .macro init;                                                          \
  .endm

#define RVTEST_RV64U RVTEST_RV32U

// register holding test number in riscv-tests framework
#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  4;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        /* basic init (avoid AUIPC/LA so core needn't implement AUIPC) */\
        lui sp, 0x20;       /* 0x00020000 */                            \
        addi sp, sp, 0;                                                 \
        li gp, 0;                                                       \
        init;                                                           \

#define RVTEST_CODE_END                                                 \
        j .

// Pass/fail: store TESTNUM to tohost and spin.
// Convention: PASS writes 1, FAIL writes (TESTNUM<<1)|1 (same as upstream).
#define RVTEST_PASS                                                     \
        fence;                                                          \
        /* tohost = 0x00001000 (64-bit tohost, write low/high words) */ \
        lui t0, 0x1;                                                    \
        addi t0, t0, 0;                                                 \
        li gp, 1;                                                       \
        sw gp, 0(t0);                                                   \
        sw x0, 4(t0);                                                   \
1:      j 1b

#define RVTEST_FAIL                                                     \
        fence;                                                          \
        /* tohost = 0x00001000 (64-bit tohost, write low/high words) */ \
        lui t0, 0x1;                                                    \
        addi t0, t0, 0;                                                 \
        /* match upstream encoding */                                   \
        sll gp, gp, 1;                                                  \
        ori gp, gp, 1;                                                  \
        sw gp, 0(t0);                                                   \
        sw x0, 4(t0);                                                   \
1:      j 1b

// Data section macros (define tohost/fromhost + signature range).
#define RVTEST_DATA_BEGIN                                               \
        .pushsection .tohost, "aw", @progbits;                          \
        .align 3;                                                       \
        .global tohost;   tohost:   .dword 0;                           \
        .global fromhost; fromhost: .dword 0;                           \
        .popsection;                                                    \
        .align 2;                                                       \
        .global begin_signature; begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 2;                                                       \
        .global end_signature; end_signature:

#endif
