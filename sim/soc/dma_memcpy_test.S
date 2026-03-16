# DMA memcpy self-test (32-bit words)
# - fill SRC region in DMEM
# - clear DST region
# - configure/start DMA
# - verify DST matches SRC
# PASS: write tohost=1
# FAIL: write tohost=code

.section .text.init
.globl _start
_start:
    # constants
    li   s0, 0x00002000      # SRC start (dmem)
    li   s1, 0x00003000      # DST start (dmem)
    li   s2, 64              # LEN bytes (multiple of 4)

    # fill SRC with pattern (word index)
    mv   t0, s0
    li   t1, 0
    li   t2, 16              # 64B / 4 = 16 words
fill_loop:
    sw   t1, 0(t0)
    addi t1, t1, 1
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, fill_loop

    # clear DST
    mv   t0, s1
    li   t1, 0
    li   t2, 16
clr_loop:
    sw   t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, clr_loop

    # DMA base 0x1000_2000
    lui  t3, 0x10002

    # program SRC/DST/LEN
    sw   s0, 0(t3)           # SRC
    sw   s1, 4(t3)           # DST
    sw   s2, 8(t3)           # LEN

    # start (CTRL bit0=1)
    li   t4, 1
    sw   t4, 12(t3)

    # poll done (STATUS bit1)
poll:
    lw   t5, 16(t3)
    andi t6, t5, 0x2
    beqz t6, poll

    # verify dst == src
    mv   t0, s0
    mv   t1, s1
    li   t2, 16
chk_loop:
    lw   a0, 0(t0)
    lw   a1, 0(t1)
    bne  a0, a1, fail_cmp
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, chk_loop

    # PASS
    lui  t0, 0x1
    li   t1, 1
    sw   t1, 0(t0)

hang:
    j hang

fail_cmp:
    li   t1, 4
    lui  t0, 0x1
    sw   t1, 0(t0)
    j hang
