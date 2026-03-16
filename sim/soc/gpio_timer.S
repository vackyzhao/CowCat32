# Minimal baremetal program for soc_top_basic
# - configure GPIO
# - wait for timer mtime to advance
# - update GPIO
# - write tohost=1 at 0x00001000

.section .text.init
.globl _start
_start:
    # GPIO base: 0x1000_0000
    lui  t0, 0x10000
    # set DIR = 0xFFFF_FFFF at +0x04
    li   t1, -1
    sw   t1, 4(t0)
    # write DATA = 0xA5A5_5A5A at +0x00
    # (use LUI+ADDI with signed 12-bit immediate)
    lui  t1, 0xA5A56
    addi t1, t1, -0x5A6
    sw   t1, 0(t0)

    # TIMER base: 0x1000_1000
    lui  t2, 0x10001
    # enable timer: CTRL bit0=1
    li   t3, 1
    sw   t3, 0(t2)

    # read initial mtime_lo
    lw   t4, 4(t2)

1:
    lw   t5, 4(t2)
    sub  t6, t5, t4
    li   a0, 20
    blt  t6, a0, 1b

    # update GPIO DATA = 0xDEAD_BEEF
    lui  t1, 0xDEADC
    addi t1, t1, -0x111
    sw   t1, 0(t0)

    # tohost at 0x0000_1000
    lui  t0, 0x1
    li   t1, 1
    sw   t1, 0(t0)

2:
    j 2b
