# UART loopback self-test
# - enable UART TX/RX + loopback
# - send a short string
# - receive back and compare
# PASS: tohost=1
# FAIL: tohost=code

.section .text.init
.globl _start
_start:
    # UART base: 0x1000_3000
    lui  t0, 0x10003

    # BAUDDIV = 8 (fast sim)
    li   t1, 8
    sw   t1, 12(t0)

    # CTRL: TX_EN=1 RX_EN=1 LOOPBACK=1
    li   t1, 0x7
    sw   t1, 16(t0)

    # message: "UART\n"
    li   s0, 'U'
    li   s1, 'A'
    li   s2, 'R'
    li   s3, 'T'
    li   s4, 10

    # send 5 bytes, then recv and compare
    mv   a0, s0
    jal  ra, send1
    mv   a0, s1
    jal  ra, send1
    mv   a0, s2
    jal  ra, send1
    mv   a0, s3
    jal  ra, send1
    mv   a0, s4
    jal  ra, send1

    mv   a0, s0
    jal  ra, recv_cmp1
    mv   a0, s1
    jal  ra, recv_cmp1
    mv   a0, s2
    jal  ra, recv_cmp1
    mv   a0, s3
    jal  ra, recv_cmp1
    mv   a0, s4
    jal  ra, recv_cmp1

    # PASS
    lui  t2, 0x1
    li   t3, 1
    sw   t3, 0(t2)

hang:
    j hang

# a0 = byte to send
send1:
    # wait TX_FULL==0 (STATUS bit1)
1:
    lw   t1, 8(t0)
    andi t1, t1, 0x2
    bnez t1, 1b
    sw   a0, 0(t0)
    ret

# a0 = expected byte
recv_cmp1:
    # wait RX_VALID==1 (STATUS bit3)
2:
    lw   t1, 8(t0)
    andi t1, t1, 0x8
    beqz t1, 2b
    lw   t2, 4(t0)   # RXDATA (pops)
    andi t2, t2, 0xFF
    bne  t2, a0, fail_rx
    ret

fail_rx:
    lui  t2, 0x1
    li   t3, 5
    sw   t3, 0(t2)
    j hang
