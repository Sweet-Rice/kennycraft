/* t_zmmul: MUL, MULH, MULHSU, MULHU on edge values (Shared page,
   Verification). For every operand pair the four results go to `results`;
   the testbench recomputes them. Then register aliasing, rd = x0 and a
   dependent instruction right after a MUL. */
#include "kc_test.h"
#define NPAIRS 14

    .section .text.start
    .globl _start
_start:
    la    s0, operands
    la    s1, results
    li    s2, NPAIRS
1:  lw    a0, 0(s0)
    lw    a1, 4(s0)
    mul    t0, a0, a1
    mulh   t1, a0, a1
    mulhsu t2, a0, a1
    mulhu  t3, a0, a1
    sw    t0, 0(s1)
    sw    t1, 4(s1)
    sw    t2, 8(s1)
    sw    t3, 12(s1)
    addi  s0, s0, 8
    addi  s1, s1, 16
    addi  s2, s2, -1
    bnez  s2, 1b

    li    a0, -3
    mul   a0, a0, a0            /* rd = rs1 = rs2: 9 */
    sw    a0, 0(s1)
    li    a1, 0x7fffffff
    mulhu a1, a1, a1            /* 0x3fffffff */
    sw    a1, 4(s1)
    li    t4, 0x1234
    mv    x0, t4
    mul   x0, a1, a1            /* x0 never written */
    sw    x0, 8(s1)
    li    a2, 1000
    li    a3, -1000
    mul   a4, a2, a3
    addi  a4, a4, 1             /* uses the product at once: -999999 */
    sw    a4, 12(s1)

    li    t0, 1
    li    t1, TB_DONE
    sw    t0, 0(t1)
2:  j     2b

    .data
operands:
    .word 0x00000000, 0x00000000
    .word 0x00000001, 0x00000001
    .word 0xffffffff, 0xffffffff
    .word 0x80000000, 0x80000000
    .word 0x80000000, 0xffffffff
    .word 0xffffffff, 0x80000000
    .word 0x7fffffff, 0x7fffffff
    .word 0x7fffffff, 0x80000000
    .word 0x80000000, 0x7fffffff
    .word 0x12345678, 0x9abcdef0
    .word 0x00000003, 0xfffffff9
    .word 0xfffffff9, 0x00000003
    .word 0x0000ffff, 0x0000ffff
    .word 0xdeadbeef, 0x00000000
results:
    .space 16 * NPAIRS + 16
