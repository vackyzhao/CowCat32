# GPIO read/write + timer mtime/cmp/status test
# PASS: write tohost=1
# FAIL: write tohost=<nonzero code>

.section .text.init
.globl _start
_start:
    # GPIO base: 0x1000_0000
    lui  t0, 0x10000

    # DIR = 0xFFFF_FFFF, then read back
    li   t1, -1
    sw   t1, 4(t0)
    lw   t2, 4(t0)
    bne  t2, t1, fail_dir

    # DATA = 0xA5A5_5A5A, then read back
    lui  t1, 0xA5A56
    addi t1, t1, -0x5A6
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, fail_data

    # TIMER base: 0x1000_1000
    lui  t3, 0x10001

    # enable timer: CTRL bit0=1
    li   t4, 1
    sw   t4, 0(t3)

    # read current mtime_lo
    lw   t5, 4(t3)

    # program cmp = mtime_lo + 30
    addi t6, t5, 30
    sw   t6, 12(t3)     # CMP_LO
    sw   x0, 16(t3)     # CMP_HI

    # wait for STATUS.hit
1:
    lw   a0, 20(t3)     # STATUS
    andi a0, a0, 1
    beqz a0, 1b

    # final write to GPIO = 0xDEAD_BEEF
    lui  t1, 0xDEADC
    addi t1, t1, -0x111
    sw   t1, 0(t0)

    # PASS
    lui  t0, 0x1
    li   t1, 1
    sw   t1, 0(t0)

hang:
    j hang

fail_dir:
    li   t1, 2
    j fail
fail_data:
    li   t1, 3
    j fail

fail:
    lui  t0, 0x1
    sw   t1, 0(t0)
    j hang
