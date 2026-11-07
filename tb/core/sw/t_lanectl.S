/* t_lanectl: custom-0 lane control on the LANES = 1 core (Tai_2 sections 1
   and 2). Starts with the wiki crt0.S prologue verbatim (Bennett page,
   Startup), which must run without an error, then checks LANEID, MASKGET,
   BALLOT, LMASK, MASKSET and MASKALL, and that with the mask at 0 no
   register is written (except BALLOT and MASKGET), no load or store reaches
   memory (a misaligned one does not halt), and branches/jumps still follow
   lane 0. Results go to res[]. */
#include "kc_test.h"

    .section .text.start
    .globl _start
_start:
    .insn r 0x0B, 7, 0, x0, x0, x0      # MASKALL
    .insn r 0x0B, 0, 0, t0, x0, x0      # t0 = LANEID
    slli  t0, t0, 10                    # lane * 1024
    li    sp, 0x10008000
    sub   sp, sp, t0                    # each lane gets its own 1 KB stack
    li    t1, 1
    .insn r 0x0B, 6, 0, x0, t1, x0      # MASKSET 1, lane 0 only
    la    a0, __bss_start
    la    a1, __bss_end
1:  bgeu  a0, a1, 2f
    sw    zero, 0(a0)
    addi  a0, a0, 4
    j     1b
2:  call  main
3:  j     3b

#define LANEID(rd)      .insn r 0x0B, 0, 0, rd, x0, x0
#define LMASK(rs)       .insn r 0x0B, 1, 0, x0, rs, x0
#define BALLOT(rd, rs)  .insn r 0x0B, 3, 0, rd, rs, x0
#define MASKGET(rd)     .insn r 0x0B, 5, 0, rd, x0, x0
#define MASKSET(rs)     .insn r 0x0B, 6, 0, x0, rs, x0
#define MASKALL         .insn r 0x0B, 7, 0, x0, x0, x0

main:
    la    s1, res
    la    s2, scratch
    sw    sp, 0(s1)             /* 0x10008000 */
    MASKGET(a0)
    sw    a0, 4(s1)             /* 1 */
    li    a0, 0x77
    LANEID(a0)
    sw    a0, 8(s1)             /* 0 */
    li    t2, 5
    BALLOT(a0, t2)
    sw    a0, 12(s1)            /* 1 */
    BALLOT(a0, zero)
    sw    a0, 16(s1)            /* 0 */

    /* Mask 0: preset every destination first. */
    li    a1, 0x11
    li    a2, 0x22
    li    a3, 0x33
    li    a4, 0x44
    li    a5, 0x55
    li    a6, 0x66
    li    a7, 0x77
    li    t4, 0x77
    li    t5, 0x77
    li    t6, 0x77
    sw    a1, 0(s2)             /* scratch = 0x11 */
    LMASK(zero)                 /* mask = 0 */
    addi  a1, zero, 0x99        /* not written */
    lui   a2, 0x12345           /* not written */
    mul   a3, t2, t2            /* not written */
    lw    a4, 0(s2)             /* no load */
    sw    zero, 0(s2)           /* no store */
    lw    a5, 1(s2)             /* misaligned but inactive: no error */
    LANEID(a6)                  /* not written */
    BALLOT(t4, t2)              /* written in every lane: 0 */
    MASKGET(t5)                 /* written in every lane: 0 */
    jal   t6, 4f                /* jumps, link not written */
    MASKALL                     /* skipped by the jal */
4:  bnez  t2, 5f                /* lane 0: taken */
    MASKALL                     /* skipped by the branch */
5:  addi  a7, zero, 1           /* not written */
    MASKSET(t2)                 /* rs1 = 5, keeps bit 0: mask = 1 */
    sw    a1, 20(s1)
    sw    a2, 24(s1)
    sw    a3, 28(s1)
    sw    a4, 32(s1)
    sw    a5, 36(s1)
    sw    a6, 40(s1)
    sw    a7, 44(s1)
    sw    t4, 48(s1)
    sw    t5, 52(s1)
    sw    t6, 56(s1)

    li    s3, 0x5A
    li    t0, 2
    MASKSET(t0)                 /* keeps bit 0 = 0: mask = 0 */
    li    s3, 1                 /* not written */
    MASKALL                     /* mask = 1 */
    MASKGET(a0)
    sw    a0, 60(s1)            /* 1 */
    sw    s3, 64(s1)            /* 0x5A */
    li    t0, 3
    LMASK(t0)                   /* rs1 != 0: stays active */
    MASKGET(a0)
    sw    a0, 68(s1)            /* 1 */

    li    t0, 1
    li    t1, TB_DONE
    sw    t0, 0(t1)
    ret

    .data
res:
    .space 4 * 18
scratch:
    .word 0
    .bss
bss_word:
    .word 0
